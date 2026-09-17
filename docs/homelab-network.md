# Homelab Networking

Reverse proxy and DNS composition for the homelab server (`reliant`) — the routing backbone every other homelab service registers into. The appliance/device layer that sits behind it (Home Assistant, Zigbee, Z-Wave, Matter, MQTT, ADS-B) is [docs/smart-home.md](smart-home.md). `custom.dns` also runs a second, independent instance on `excelsior` — see § Second DNS Instance (excelsior) below.

The full option-to-module table is [docs/architecture.md § Custom Options § Homelab services](architecture.md#homelab-services) — that catalogue is canonical for every `custom.*` option in the repo.

## Reverse Proxy And DNS

The two compose to give every service a real HTTPS name on the LAN.

`custom.traefik` requests a **wildcard** certificate for `*.<domain>` using a DNS-01 challenge, so no service is ever exposed to the internet for validation. The provider credentials come from an agenix secret via `acme.environmentFile` (for Cloudflare, a file containing `CLOUDFLARE_DNS_API_TOKEN=...` -- lego's actual env var name for this provider).

The ACME cert declares `reloadServices = ["traefik.service"]`. Without it Traefik never learns a new certificate exists and keeps serving whatever it loaded at its own startup — the self-signed fallback, if ACME had not yet succeeded.

`custom.dns` runs two resolvers:

- **unbound** on port 5335 — recursive, DNSSEC-validating, and the split-horizon authority for the local domain. Each name in `custom.dns.subdomains` becomes an `A` record pointing at `custom.dns.lanIp`.
- **AdGuard Home** on port 53 — the LAN-facing ad-blocking resolver, with unbound as its only upstream.

Point the LAN's DHCP at the host's reserved IP for DNS Server 1, and clients get both ad-blocking and local name resolution. Port 5335 stays open so a client can bypass AdGuard while keeping local resolution.

Two design decisions in `modules/dns.nix` are load-bearing and easy to undo by accident:

- The local zone is `transparent`, not `static`. `static` answers only what is in `local-data` and NXDOMAINs everything else in the zone, including SOA and NS. That breaks ACME DNS-01 issuance, because lego runs on this host and finds the Cloudflare zone by walking SOA records up from `_acme-challenge.<domain>`. With `static`, our own resolver reported the domain did not exist, so lego walked past it to the public suffix and failed. `transparent` still answers the configured subdomains from `local-data` but falls through to real recursion for everything else.
- unbound is ordered after `time-sync.target`, and `systemd-time-wait-sync` is force-enabled. The Pi has no battery-backed clock, so on every boot the kernel clock starts wrong until timesyncd's first NTP sync. Starting unbound before that made every DNSSEC lookup fail with "DNSKEY rrset is not secure" — real signatures failing against a clock that had not caught up. There is no circular dependency: the box resolves via the DHCP-provided nameservers at boot, not through unbound.

`custom.dns.lanSubnet` defaults to `192.168.1.0/24`. Override it if the host is not on that subnet, or unbound's `access-control` will not cover direct bypass queries from its own LAN.

### Troubleshooting: iOS Client Bypassing LAN DNS (Private Relay)

Symptom: an iPhone on the LAN, with correct DHCP-assigned DNS, gets a TLS certificate error visiting a `*.coppertop.ca` service and lands on the Unifi controller's web console instead of the expected page.

Root cause: iOS's per-Wi-Fi-network "Hide IP Address" setting ("Limit IP Address Tracking" on older iOS; tied to iCloud Private Relay) reroutes that device's DNS and traffic for that network through Apple's relay infrastructure. It bypasses the LAN's DNS servers even though the Wi-Fi network's DNS settings correctly show them. The device never gets the split-horizon answer from unbound (see § Reverse Proxy And DNS above) and instead reaches something public — in the observed case, the Unifi gateway's own console on port 443.

Fix: on the device, Settings → Wi-Fi → (ⓘ) next to the home network → turn off "Hide IP Address"/"Limit IP Address Tracking". This is per-network and per-device — it persists once set, but must be applied individually on every Apple device that needs to reach `*.coppertop.ca`, since there's no way to enforce it network-side.

## Traefik Route Registration

Service modules register their own routes rather than requiring a central table. Each module does this, guarded on `custom.traefik.enable`:

```nix
services.traefik.dynamicConfigOptions.http = mkTraefikRoute {
  name = "homeassistant";
  subdomain = "home";
  port = 8123;
  inherit (config.custom.traefik.acme) domain;
};
```

`lib/traefik-route.nix` builds the router and load-balancer pair. It targets `http://127.0.0.1:<port>` — the literal IPv4 loopback, not `localhost`. `localhost` can resolve to `::1` depending on system resolution order, and a service with a strict reverse-proxy trust check rejects the request outright if the proxy connects over `::1`. Home Assistant, whose `trusted_proxies` lists only `127.0.0.1`, returned 400 in exactly this way while AdGuard's route (which has no such check) worked.

When the target service's own listen port is itself a configurable option (rather than fixed, like dump1090's), pass the live option value — `port = config.services.<foo>.port;` — not a literal. `modules/dns.nix`'s own AdGuard route does this (`config.services.adguardhome.port`, upstream default 3000). A hardcoded `3000` would silently decouple the route from the real port the moment that option is ever overridden. That matters because `custom.bambuddy`'s virtual-printer feature hardcodes ports 3000/3002 upstream and can't be enabled on this host until AdGuard moves off 3000 — see `hosts/reliant/README.md` § Bambuddy.

## Authelia Forward-Auth (lldap + Authelia SSO)

`custom.lldap` (`modules/lldap.nix`) and `custom.authelia` (`modules/authelia.nix`) add web-app single sign-on in front of Traefik, for whichever internal admin UIs opt in. This is web SSO only — Windows machine-login unification is out of scope (Samba AD rejected as too heavy, pGina as poorly maintained). Linux login unification via lldap+sssd is viable (lldap ships an official PAM/sssd example) but a separate future item.

- **lldap** (`custom.lldap`) is the directory backend, chosen over Samba AD or OpenLDAP for its simpler admin UX and upstream `bootstrap.sh` script, which declaratively reconciles users/groups from JSON config against lldap's GraphQL API on every run. `modules/lldap.nix` renders `custom.lldap.bootstrap.users`/`.groups` to JSON at build time and runs the script as a systemd oneshot (`lldap-bootstrap.service`) on every change. `custom.lldap.bootstrap.cleanup` (`DO_CLEANUP`) makes those lists the real source of truth — anything not declared gets pruned. Passwords are settable declaratively via a user's `passwordFile`, used here for Authelia's own bind account. Real household accounts are a **documented TODO** — see `hosts/reliant/README.md` § lldap.
  - `bootstrap.sh` is pinned to the exact lldap release `pkgs.lldap.version` builds, not `main`. If nixpkgs bumps lldap, this hash needs bumping too — `fetchurl` fails loudly rather than running a mismatched script.
  - Known non-blocking upstream caveat: lldap/lldap#745 reports possible duplicate group memberships across repeated bootstrap runs with `DO_CLEANUP` on. Not confirmed present here — watch `journalctl -u lldap-bootstrap` across a few reruns rather than designing around it.
- **Authelia** (`custom.authelia`) is the Traefik forward-auth portal, backed by lldap via LDAP. 2FA is **TOTP and WebAuthn only** — Duo is deferred. Its bind account (`custom.authelia.ldap.bindDn`) belongs to lldap's `lldap_strict_readonly` group, never `lldap_admin` — it only reads user/group attributes.
  - The LDAP bind password isn't one of nixpkgs' `services.authelia.instances.<name>.secrets.*` fields (JWT/OIDC/session/storage only) — it goes through Authelia's own `AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD_FILE` env-var convention, bypassing `LoadCredential`. The file must be directly readable by the `authelia-main` system user, so the agenix secret's `owner` needs to be that, not root.
  - No SMTP notifier is configured — password-reset emails write to a local file instead of sending. A real gap in the flow, not a design choice: SMTP credentials weren't fabricated for a server that doesn't exist yet.
  - Session storage is the in-memory provider (no Redis) — sessions don't survive an Authelia restart. Fine at this scale; Redis is a future option.

### The forward-auth middleware and opting a route in

`modules/authelia.nix` defines exactly one Traefik middleware, `authelia@file` (Traefik's own `<name>@<provider>` reference syntax for anything declared through `dynamicConfigOptions`, not a literal filename):

```nix
services.traefik.dynamicConfigOptions.http.middlewares.authelia.forwardAuth = {
  address = "http://127.0.0.1:9091/api/authz/forward-auth";
  trustForwardHeader = true;
  authResponseHeaders = ["Remote-User" "Remote-Groups" "Remote-Email" "Remote-Name"];
};
```

"Gated" here means a Traefik-layer forward-auth check only — it doesn't by itself give the backend app awareness of who logged in. `forwardAuth` does forward `Remote-User`/`Remote-Groups`/`Remote-Email`/`Remote-Name` headers, so an app taught to trust them could skip its own login, but none of the apps behind this middleware have a login of their own yet. That's exactly why Home Assistant isn't on this list — see below for why forward-auth is the wrong tool for a service with a real login, where OIDC is the actual answer.

A route opts in by adding `middlewares = ["authelia@file"]` to its own router. `lib/traefik-route.nix` grew an optional `middlewares` parameter for exactly this (empty by default — most routes still carry no auth middleware at all):

```nix
services.traefik.dynamicConfigOptions.http = mkTraefikRoute {
  name = "adguard";
  # ...
  middlewares = optional (config.custom.authelia.enable && builtins.elem cfg.adminSubdomain config.custom.authelia.protectedSubdomains) "authelia@file";
};
```

A manually-defined router (the `dns2`/`jellyfin`/DCS-control shape, § Second DNS Instance below) just adds the key directly, the same way `dns2` does on `reliant` today.

`custom.authelia.protectedSubdomains` is the single list that drives both sides: it becomes Authelia's own `access_control` rules (`two_factor` policy, `default_policy = "deny"`) **and** documents which routes are expected to carry the middleware. Adding a subdomain to that list does not, by itself, protect anything; the router still has to add `middlewares = ["authelia@file"]` itself.

On `reliant` today that's `dns1` (this host's own AdGuard admin UI, gated from `modules/dns.nix`), `dns2` (excelsior's AdGuard admin UI, gated from the manual router in `hosts/reliant/configuration.nix`), `zigbee.coppertop.ca` (Zigbee2MQTT), and `bambuddy.coppertop.ca`. `dcs.coppertop.ca`/`dcs-control.coppertop.ca` (excelsior's DCS webtop desktop and start/stop control page) are also on the list — but **not** the `dcs-control` `/hooks` webhook router, which is called machine-to-machine and would break if Authelia redirected it to a login page. None of these have a login of their own.

The Zigbee and Bambuddy routers are self-registered inside `modules/zigbee.nix` (owned by `smart-home`) and `modules/bambuddy.nix`. Rather than edit those files, `reliant`'s `configuration.nix` layers `middlewares = ["authelia@file"]` onto their existing router entries as a data overlay — the same freeform-deep-merge mechanism `dns2`'s manual router uses. This is the pattern for gating a cross-domain route without editing the owning module: add the router's name and `middlewares` key under `services.traefik.dynamicConfigOptions.http.routers` in the host's own `configuration.nix`, and the module system merges it with that router's `rule`/`service`/`tls` defined elsewhere.

`home.coppertop.ca` (Home Assistant) is deliberately **not** on this list. Forward-auth is the wrong mechanism for a service that already has its own real login — gating it this way adds a redundant second login, not SSO. Real SSO for Home Assistant is built as a distinct piece of functionality, Authelia running as an OpenID Connect 1.0 provider — see § OIDC Provider below — not as a variant of `protectedSubdomains`.

### OIDC Provider

Authelia can run as an OpenID Connect 1.0 provider from the same instance that serves the forward-auth portal, both gated independently (`protectedSubdomains` vs `oidc.enable`). This is the mechanism for giving a service **with its own real login** actual SSO, instead of the redundant-second-login problem forward-auth would create. Today the only registered client is Home Assistant, via the third-party [`hass-oidc-auth`](https://github.com/christiaangoossens/hass-oidc-auth) HACS component, following Authelia's own [Home Assistant OIDC integration guide](https://www.authelia.com/integration/openid-connect/clients/home-assistant/) (fetched at this repo's pinned Authelia version, `v4.39.20`).

`custom.authelia.oidc` (`modules/authelia.nix`):

- `enable` turns on `identity_providers.oidc` and requires two new secrets:
  - `issuerPrivateKeyFile` — an RSA private key (PKCS#8 or PKCS#1, ≥2048 bits), Authelia's OIDC issuer signing key. Maps to `secrets.oidcIssuerPrivateKeyFile`, which nixpkgs auto-templates into `identity_providers.oidc.jwks` at startup — `jwks` is never written directly in this module's `settings`.
  - `hmacSecretFile` — a random ≥64-character string signing OIDC JWTs (`identity_providers.oidc.hmac_secret`). Maps to `secrets.oidcHmacSecretFile`.
- `homeAssistant.enable` registers Home Assistant as an OIDC client (requires `oidc.enable`). `clientId` (default `home-assistant`) and `redirectUri` (default `https://home.${domain}/auth/oidc/callback`) both have usable defaults — only `clientSecretHashFile` needs a value.
- `homeAssistant.clientSecretHashFile` — not a plain "point at an agenix path" secret. Authelia's `identity_providers.oidc.clients[].client_secret` stores a **pbkdf2-sha512 hash**, not the raw secret, and there's no `oidcClientSecretFile` in nixpkgs' `secrets.*` fields — so it's wired the same way `ldap.bindPasswordFile` is: read directly at runtime, not through `LoadCredential`. The entire Home Assistant OIDC client entry (client ID, redirect URI, scopes, `client_secret`) is rendered as one generated `settingsFile`, with `client_secret` substituted via Authelia's own Go-template `secret` function reading the agenix path directly. It has to be the *whole* client entry in one file, not split across `settings` and a secret fragment, because Authelia's config-file merging replaces whole list values rather than merging list items.

Generate the two provider-level secrets and the client secret hash:

```bash
# oidc-issuer-private-key
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048
# oidc-hmac-secret
openssl rand -base64 64 | tr -d '\n=+/' | head -c 64
# oidc-client-secret-home-assistant-hash -- prints both the raw secret
# (goes into Home Assistant's own auth_oidc.client_secret, not this repo)
# and its digest (goes into this file, and only this file)
nix run nixpkgs#authelia -- crypto hash generate pbkdf2 --variant sha512 --random
```

What this module does **not** cover: Home Assistant's own side (installing the `hass-oidc-auth` HACS component, HA's `auth_oidc` configuration block). That's `smart-home`'s (`modules/home-assistant.nix`, `hosts/reliant/home-assistant/`). The values it needs from this side:

| What HA needs | Value |
| --- | --- |
| OIDC issuer / discovery URL | `https://auth.coppertop.ca/.well-known/openid-configuration` (Authelia's own portal subdomain, `custom.authelia.subdomain`) |
| `client_id` | `home-assistant` (`custom.authelia.oidc.homeAssistant.clientId`) |
| `client_secret` | The **raw** (pre-hash) secret from generating `oidc-client-secret-home-assistant-hash` above — not the agenix path, and not the hash stored there. HA's own config needs the plaintext value; Authelia stores only the digest. |
| Redirect URI | `https://home.coppertop.ca/auth/oidc/callback` (`custom.authelia.oidc.homeAssistant.redirectUri`) — `hass-oidc-auth`'s fixed callback path |
| Authorization/token/userinfo endpoints | Not hardcoded anywhere — `hass-oidc-auth` discovers them from the discovery URL above, per Authelia's OpenID Connect 1.0 Discoverable Endpoints (`/api/oidc/authorization`, `/api/oidc/token`, `/api/oidc/userinfo` under `auth.coppertop.ca`) |

### Self-Lockout Rule

Neither lldap's admin UI route (`ad.coppertop.ca`) nor Authelia's own portal route (`auth.coppertop.ca`) may ever carry the `authelia` middleware. Authelia authenticates against lldap, so gating either behind Authelia risks a total lockout if lldap is down, mid-bootstrap, or misconfigured, with no way back short of console/SSH access. Both rely instead on their own native login plus network-level scoping (Traefik-proxied at `127.0.0.1` like everything else). `modules/authelia.nix` asserts on this directly: `protectedSubdomains` may not contain `custom.lldap.subdomain` or `custom.authelia.subdomain` itself.

## Second DNS Instance (excelsior)

AdGuard Home has no native clustering — every real-world HA setup for it is a DIY workaround. This repo runs **dual independent instances**: `reliant`'s existing one, plus a second, fully separate `custom.dns` on `excelsior`, sharing no config or state. Router/DHCP should hand out both reserved IPs as primary/secondary DNS for real redundancy — that's a router-side step, not managed by this repo.

Both admin UIs are reachable without an SSH tunnel, proxied through Traefik:

- `dns1.coppertop.ca` → the host's own AdGuard UI, self-registered by `modules/dns.nix` the normal way (§ Traefik Route Registration above), with `custom.dns.adminSubdomain = "dns1";` overriding the module's `"dns"` default now that a second instance exists to disambiguate from.
- `dns2.coppertop.ca` → `excelsior`'s AdGuard UI. This **cannot** use the module's self-registration, which only ever targets `127.0.0.1` — Traefik runs on a different host than the service it's proxying. Instead, the Traefik host's `configuration.nix` defines this router by hand, pointing `lib/traefik-route.nix`'s pattern at `excelsior`'s real LAN IP:

  ```nix
  services.traefik.dynamicConfigOptions.http = {
    routers.dns2 = {
      rule = "Host(`dns2.coppertop.ca`)";
      service = "dns2";
      tls = {};
    };
    services.dns2.loadBalancer.servers = [{url = "http://192.168.1.10:3000";}];
  };
  ```

  This merges fine alongside every module-contributed route on that host since `dynamicConfigOptions` is a TOML freeform type.

`excelsior`'s AdGuard admin UI (default port 3000) is bound to `excelsior`'s own LAN IP and reachable only from `reliant`. `modules/dns.nix` sets `openFirewall = false` — the nixpkgs AdGuard module's `openFirewall` opens the admin port with no source restriction at all, not appropriate for a service with weak default auth. `hosts/excelsior/configuration.nix` instead adds a `firewall.extraCommands` rule scoped to `reliant`'s IP (`192.168.20.15`). `reliant`'s own AdGuard instance needs no such rule — Traefik reaches it over `127.0.0.1` regardless of the firewall.

`reliant` is the only host carrying this manual `dns2` router and running Traefik — the "Traefik never runs a second copy" invariant this section otherwise assumes.

## DCS On-Demand Start/Stop And Remote Control (excelsior)

`excelsior` also runs `custom.dcsServer` (DCS World dedicated server). Two related but distinct things are proxied here: an on-demand start/stop control page at `dcs-control.coppertop.ca` (works remotely), and DCS's own WebGUI (does **not** work remotely through any proxy, by DCS's own design — see below). The webtop desktop actually used day-to-day gets the bare `dcs.coppertop.ca` name; see § DCS's webtop desktop is proxied cross-host below.

### On-demand start/stop

DCS runs 24/7 by default, real resource cost for a game server idle most of the time. `custom.dcsServer.startAtBoot = false;` on `excelsior` stops the container auto-starting on boot — the systemd units still exist and can be started on demand, they just don't come back on their own. `custom.dcsServer.control.enable = true;` stands up the on-demand surface: a static status/Start/Stop page (nginx) plus a narrowly-scoped `webhook` (adnanh/webhook) instance that runs `systemctl start`/`stop` on those units, bound to excelsior's LAN IP and firewall-restricted to `reliant` only.

The webhook process runs as a dedicated unprivileged `dcs-control` user, not root. `security.sudo.extraRules` grants it a `NOPASSWD` rule scoped to the *exact* two `systemctl start`/`stop` command lines — nothing broader. Stopping is **manual only**; no idle-timeout auto-stop, since a false-idle read stopping a live session is worse than a forgotten manual stop.

`reliant`'s `configuration.nix` proxies `dcs-control.coppertop.ca` at this control page/webhook, same manual-router shape as `dns2`:

```nix
routers.dcsControlHooks = {
  rule = "Host(`dcs-control.coppertop.ca`) && PathPrefix(`/hooks`)";
  service = "dcsControlHooks";
  priority = 100;
  tls = {};
};
routers.dcsControlPage = {
  rule = "Host(`dcs-control.coppertop.ca`)";
  service = "dcsControlPage";
  priority = 1;
  tls = {};
};
```

Both routers need explicit priorities: `dcsControlPage`'s rule (`Host(...)`) is a substring of `dcsControlHooks`'s rule (`Host(...) && PathPrefix(/hooks)`). Without them, Traefik's default rule-length-based priority for the unprefixed page router beat a previous hardcoded priority on the hooks router alone, silently routing `/hooks/*` to nginx (a raw 404) instead of the webhook.

`dcs-control.coppertop.ca` has no auth beyond the source-IP restriction — general Traefik auth in front of it is a deliberate follow-up, done holistically rather than one router at a time. Starting the container via the control page does **not** by itself load a DCS mission — a separate, unrelated gap (`Mission list is empty, server not started.` in DCS's own log).

### Mission upload

The same control page also has a `.miz` upload form, backed by a third `webhook` hook, `/hooks/dcs-upload-mission` — an alternative to `scp`-ing a mission file over SSH. The browser POSTs the file as a raw (non-multipart) body with the filename in an `X-Filename` header, since `adnanh/webhook`'s `pass-file-to-command` only pulls file content from `source: payload` for JSON-decodable parts; a real binary upload has to go in as `source: raw-request-body` instead.

The unprivileged `dcs-control` user can't write into the DCS install directly (owned by the container's `PUID`/`PGID`, 1000:1000), so uploads are privilege-separated the same way start/stop are: the webhook script stages the file under `/var/lib/dcs-control/uploads`, then hands off to a **fixed, zero-argument** `sudo` command that re-sanitizes the staged filename itself and `install`s it into `custom.dcsServer.control.missionsDir` as `1000:1000`. Sudoers can't safely pattern-match an arbitrary filename on a command line, which is why the privileged script takes no arguments and reads everything from a fixed staging path.

Uploading only gets the file onto the host; DCS still won't run it until it's added to the active mission list through the tunneled webtop's WebGUI (see `hosts/excelsior/README.md`) — the same manual step required today, just without an SSH tunnel to get the file there.

### DCS's own WebGUI does not work through any reverse proxy

`custom.dcsServer.webGuiPort` (default 8088) is DCS's own remote-control WebGUI backend (`POST /encryptedRequest`, served by `DCS_server.exe` itself). **This cannot be reverse-proxied for remote use, by design.** DCS's server deliberately rejects `/encryptedRequest` calls that don't arrive from a genuinely local connection — a real security boundary, not a bug. A same-origin nginx proxy with a patched `app.js` was built and tested here; every variation (loopback-bound backend, forced `credentials: "omit"`, forced `Host: 127.0.0.1`) still got `422 Unprocessable Entity` from DCS itself. See `hosts/excelsior/README.md` § Known Gotchas before attempting this again.

DCS's remote-control mechanism instead assumes ports 8088 (WebGUI) and 10308 (game) are directly port-forwarded from the WAN, with no HTTP-layer proxy in the path — per DCS's own log (`Registering HTTP control interface as <public-ip>:8088 (port is assumed to be open)`). That router-level port-forward is **not** managed by this repo. `webGuiBindAddress` is bound to `excelsior`'s LAN IP for exactly that, and `networking.firewall.allowedTCPPorts` opens 8088 broadly, same as the game port — real remote DCS clients can come from any public IP, not just `reliant`'s.

### DCS's webtop desktop is proxied cross-host — unlike the WebGUI above

`custom.dcsServer.desktopPort` (default 3000, overridden to 3001 on `excelsior` since the default collides with AdGuard's admin UI) is a [linuxserver.io webtop](https://docs.linuxserver.io/images/docker-webtop/) noVNC desktop, not the WebGUI's `/encryptedRequest` API above. noVNC is a plain websocket video/input stream with no origin check, so the WebGUI limitation doesn't apply — the desktop proxies cross-host fine. `reliant`'s `configuration.nix` proxies it at the bare `dcs.coppertop.ca` name (the desktop actually used day-to-day), with the start/stop control page moved to the more explicit `dcs-control.coppertop.ca` — same manual-router shape as `dcs-control`/`dns2`/Jellyfin:

```nix
routers.dcsDesktop = {
  rule = "Host(`dcs.coppertop.ca`)";
  service = "dcsDesktop";
  tls = {};
};
services.dcsDesktop.loadBalancer.servers = [{url = "http://192.168.1.10:3001";}];
```

`custom.dcsServer.desktopBindAddress` is bound to `excelsior`'s LAN IP (not loopback) and firewall-restricted to `reliant`'s IP only, same posture as the control page: webtop has weak default auth and no Traefik middleware in front, so the firewall is the only gate. Opening a browser tab is now enough to reach the DCS launcher/WebGUI *from inside* the webtop desktop (same-origin there, so DCS's local-connection check still passes) — the SSH-tunnel path (`ssh -L 3001:localhost:3001`) still works too, just no longer required.

## Jellyfin (excelsior)

`excelsior` also runs `custom.jellyfin` (`modules/jellyfin.nix`), backed by a NAS-mounted media library (`hosts/excelsior/media.nix`). Unlike its self-hosted usage (self-registering a Traefik route when `custom.traefik.enable` is set on the same host), `excelsior` runs no Traefik of its own: `reliant`'s Traefik proxies it cross-host, `jellyfin.coppertop.ca` → `excelsior:8096`, the same manual-router pattern as `dns2` and the DCS control page above:

```nix
services.traefik.dynamicConfigOptions.http = {
  routers.jellyfin = {
    rule = "Host(`jellyfin.coppertop.ca`)";
    service = "jellyfin";
    tls = {};
  };
  services.jellyfin.loadBalancer.servers = [{url = "http://192.168.1.10:8096";}];
};
```

Jellyfin has its own real account system, unlike AdGuard's admin UI or the DCS control page, so there's no Traefik auth concern here. The port is still closed off at the network layer the same way: `custom.jellyfin.openFirewall = false;` on `excelsior`, plus a `networking.firewall.extraCommands` rule scoped to `reliant`'s reserved LAN IP (`192.168.20.15`) on port 8096 — the same `reliantIp` restriction already used for the DCS control page and AdGuard admin UI.

## Dynamic DNS

`custom.ddns` (`modules/ddns.nix`) runs `ddclient` to keep `coppertop.ca`'s apex A record pointed at this residential connection's current public IP — this ISP has no static IP. It updates only that record: `*.coppertop.ca` is already a CNAME to the apex, so every subdomain follows automatically. That CNAME is managed by hand in Cloudflare, not by this module, and only needs to exist once.

Since every subdomain rides the apex update, no Cloudflare change is needed to add a new subdomain later — this is what lets `excelsior`'s game servers be reachable by friends purely by adding a router port-forward, with no DNS-side follow-up. See `hosts/excelsior/README.md` § Services And URLs and § Provisioning § Optional follow-ups.

It reuses `custom.traefik.acme`'s existing Cloudflare API token (`traefik/cloudflare-api-token.age`) rather than a second secret. That file is formatted as an `EnvironmentFile=` line (`CLOUDFLARE_DNS_API_TOKEN=<token>`) for `security.acme`, not the bare token ddclient's `passwordFile` wants — so `modules/ddns.nix` runs `ddclient` as the `traefik` system user (this file's existing owner) and strips the prefix into a private, owner-only file at service start. See § Known Gotchas below for why this isn't the more obvious `services.ddclient.passwordFile = apiTokenFile;` one-liner.

### Verifying it worked

- `journalctl -u ddclient -n 50` on `reliant` — a successful run logs the Cloudflare zone lookup and, only on an actual IP change, `SUCCESS` per record; an unchanged IP logs nothing new by design.
- Force a run: `sudo systemctl start ddclient.service && journalctl -u ddclient -f`.
- Query a public resolver directly, bypassing the LAN's own AdGuard/unbound: `dig @1.1.1.1 +short coppertop.ca` and `dig @1.1.1.1 +short anything.coppertop.ca` should both return this network's current public IP (the subdomain resolves through the CNAME to the apex). Check against `curl -s https://ifconfig.me` run from `reliant` itself.

## Adding A New Homelab Service

1. Write `modules/<service>.nix` exposing `custom.<service>`, following the existing modules' shape: `mkEnableOption`, the service config, and a `mkIf config.custom.traefik.enable` block registering its route with `mkTraefikRoute`.
2. Add it to `modules/default.nix`.
3. Enable it in the host's `configuration.nix` under `custom`.
4. Add its subdomain to `custom.dns.subdomains` so the name resolves on the LAN.
5. If it holds credentials, add an agenix secret — see [docs/secrets.md](secrets.md#creating-or-rotating-a-secret) — and reference the `/run/agenix/<name>` path from the module option.
6. If it holds state worth keeping, add a `custom.backups.users.<service>` entry with explicit `paths`. Verify the real state directory with `ls` on the host first; it is not always what the service name suggests.
7. Document the machine-specific facts (URL, first-run wizard, device quirks) in that host's README.

If the new service is a Home Assistant integration rather than a standalone appliance, also see [docs/smart-home.md § Choosing extraComponents](smart-home.md#choosing-extracomponents) and the automation-file conventions in that doc.

## Known Gotchas

- `custom.ddns`'s `ddclient` service does not use `services.ddclient.passwordFile` pointed straight at `custom.traefik.acme.environmentFile`: that file is an `EnvironmentFile=`-format line (`CLOUDFLARE_DNS_API_TOKEN=<token>`), but `passwordFile` substitutes a file's entire content verbatim, so the literal string would be sent to Cloudflare as the credential and every update would fail auth. `modules/ddns.nix` strips the prefix into a private file at service start instead — see § Dynamic DNS above.
- `CLOUDFLARE_DNS_API_TOKEN` is lego's actual env var for the Cloudflare provider — confirmed against the real secret's content on `reliant`, not assumed. `modules/traefik.nix`'s option description previously gave the wrong example (`CF_DNS_API_TOKEN`) and broke the first deploy's `ExecStartPre` extraction script with a silent "no line found" failure; the description is now fixed.
- The prefix-stripping step needed `DynamicUser = false` and a fixed `User = "traefik"` on `ddclient.service`: with `DynamicUser` (the module's default), the service gets a fresh, unpredictable UID per invocation, and the ExecStartPre step reading the real secret and writing the derived one would need access to files it doesn't own. Fixing the service to the `traefik` user (already the secret's owner) keeps every step under one known identity.
- ddclient's `cloudflare` protocol only `PATCH`es a DNS record that already exists at Cloudflare, of the expected type — it never creates one. `custom.ddns` deliberately lists only the apex in `services.ddclient.domains`, not `*.coppertop.ca` — that name is a CNAME, not an A record, and pointing ddclient at it fails every run with `no 'A' record at Cloudflare`. The wildcard CNAME still needs to exist in the zone for subdomains to resolve; it's just not something ddclient itself touches.
- `custom.ddns` sets `usev6 = ""` deliberately, overriding `services.ddclient`'s default IPv6 probing. This zone tracks IPv4 only; leaving `usev6` default produces a spurious `no 'AAAA' record at Cloudflare` failure every interval for a record this setup was never asked to manage.
- `lib/traefik-route.nix`'s `middlewares` parameter and `modules/authelia.nix`'s forward-auth middleware definition both write to `services.traefik.dynamicConfigOptions.http`. Writing both from a single attrset literal inside one module is a plain Nix "attribute already defined" error, not a module-system merge conflict. Fix: split them into two separate `mkMerge` list elements (each its own `mkIf config.custom.traefik.enable {...}`) — the module system already merges independent contributions to the same freeform option across fragments, the way `dns.nix`/`home-assistant.nix`/`zigbee.nix` coexist on it. Keep every logically distinct contribution in its own `mkMerge` element, even within a single module.
- Authelia's LDAP bind password isn't one of nixpkgs' `services.authelia.instances.<name>.secrets.*` fields (JWT/OIDC/session/storage only) — it goes through Authelia's own environment-variable secrets convention instead (`AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD_FILE`, per Authelia's own secrets docs), bypassing `LoadCredential`. The secret file must be directly readable by the `authelia-main` system user, so its agenix `owner` needs to be `authelia-main`, not root or another service's user.
- This lldap/Authelia design was written without a working `nix build` in the authoring environment. Every config field, secret env var, and script interface was checked against the real pinned nixpkgs modules and upstream source/docs, not guessed — but the actual `nixos-rebuild switch` on `reliant` was the first real test of whether it all fit together. See the two entries below for what that first deploy found.
- **Confirmed on the real first deploy**: `modules/lldap.nix`'s rewrite for `reliant` had dropped the static `lldap` system user, leaving `services.lldap` on its default `DynamicUser`, while `hosts/reliant/secrets.nix` still set `owner = "lldap"` on two agenix secrets. The switch failed activation with `chown: invalid user: 'lldap:0'`, since agenix chowns secrets before any systemd unit — and therefore before a `DynamicUser`'s transient UID — exists. Fixed by restoring the static user/group and forcing `DynamicUser = false`.
- **Also confirmed live**: `authelia-main.service` only depended on `lldap.service` being up, not on `lldap-bootstrap.service` having finished reconciling the `authelia` bind account. On the real first deploy this raced and crash-looped twice — `connection refused` while lldap was still starting, then `LDAP Result Code 49 "Invalid Credentials"` while bootstrap was still creating that account — before `Restart=on-failure` got it up on the third attempt. `modules/authelia.nix` now blocks `authelia-main.service` on `lldap-bootstrap.service` explicitly instead of relying on the restart policy to paper over the race.
