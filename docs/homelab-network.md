# Homelab Networking

Reverse proxy and DNS composition for the homelab server (`reliant`) — the
routing backbone every other homelab service registers into. The
appliance/device layer that sits behind it (Home Assistant, Zigbee, Z-Wave,
Matter, MQTT, ADS-B) is [docs/smart-home.md](smart-home.md). `custom.dns`
also runs a second, independent instance on `excelsior` — see § Second DNS
Instance (excelsior) below.

The full option-to-module table is
[docs/architecture.md § Custom Options § Homelab services](architecture.md#homelab-services) —
that catalogue is canonical for every `custom.*` option in the repo.

## Reverse Proxy And DNS

The two compose to give every service a real HTTPS name on the LAN.

`custom.traefik` requests a **wildcard** certificate for `*.<domain>` using a
DNS-01 challenge, so no service is ever exposed to the internet for validation.
The provider credentials come from an agenix secret via
`acme.environmentFile` (for Cloudflare, a file containing
`CLOUDFLARE_DNS_API_TOKEN=...` -- lego's actual env var name for this
provider; confirmed against the real secret, not assumed).

The ACME cert declares `reloadServices = ["traefik.service"]`. Without it Traefik
never learns a new certificate exists and keeps serving whatever it loaded at its
own startup — the self-signed fallback, if ACME had not yet succeeded.

`custom.dns` runs two resolvers:

- **unbound** on port 5335 — recursive, DNSSEC-validating, and the split-horizon
  authority for the local domain. Each name in `custom.dns.subdomains` becomes an
  `A` record pointing at `custom.dns.lanIp`.
- **AdGuard Home** on port 53 — the LAN-facing ad-blocking resolver, with unbound
  as its only upstream.

Point the LAN's DHCP at the host's reserved IP for DNS Server 1, and clients get
both ad-blocking and local name resolution. Port 5335 stays open so a client can
bypass AdGuard while keeping local resolution.

Two design decisions in `modules/dns.nix` are load-bearing and easy to undo by
accident:

- The local zone is `transparent`, not `static`. `static` answers only what is in
  `local-data` and NXDOMAINs everything else in the zone, including SOA and NS.
  That breaks ACME DNS-01 issuance, because lego runs on this host and finds the
  Cloudflare zone by walking SOA records up from `_acme-challenge.<domain>`. With
  `static`, our own resolver reported the domain did not exist, so lego walked
  past it to the public suffix and failed. `transparent` still answers the
  configured subdomains from `local-data` but falls through to real recursion for
  everything else.
- unbound is ordered after `time-sync.target`, and
  `systemd-time-wait-sync` is force-enabled. The Pi has no battery-backed clock,
  so on every boot the kernel clock starts wrong until timesyncd's first NTP
  sync. Starting unbound before that made every DNSSEC lookup fail with "DNSKEY
  rrset is not secure" — real signatures failing against a clock that had not
  caught up. There is no circular dependency: the box resolves via the
  DHCP-provided nameservers at boot, not through unbound.

`custom.dns.lanSubnet` defaults to `192.168.1.0/24`. Override it if the host is
not on that subnet, or unbound's `access-control` will not cover direct bypass
queries from its own LAN.

### Troubleshooting: iOS Client Bypassing LAN DNS (Private Relay)

Symptom: an iPhone on the LAN, with correct DHCP-assigned DNS, gets a TLS
certificate error visiting a `*.coppertop.ca` service and lands on the Unifi
controller's web console instead of the expected page.

Root cause: iOS's per-Wi-Fi-network "Hide IP Address" setting ("Limit IP
Address Tracking" on older iOS; tied to iCloud Private Relay) reroutes that
device's DNS and traffic for that network through Apple's relay
infrastructure, bypassing the LAN's DNS servers even though the Wi-Fi
network's DNS settings correctly show them. The device never gets the
split-horizon answer from unbound (see § Reverse Proxy And DNS above) and
instead reaches something public — in the observed case, the Unifi gateway's
own console on port 443.

Fix: on the device, Settings → Wi-Fi → (ⓘ) next to the home network → turn off
"Hide IP Address"/"Limit IP Address Tracking". This is per-network and
per-device — it persists once set, but must be applied individually on every
Apple device that needs to reach `*.coppertop.ca`, since there's no way to
enforce it network-side.

## Traefik Route Registration

Service modules register their own routes rather than requiring a central table.
Each module does this, guarded on `custom.traefik.enable`:

```nix
services.traefik.dynamicConfigOptions.http = mkTraefikRoute {
  name = "homeassistant";
  subdomain = "home";
  port = 8123;
  inherit (config.custom.traefik.acme) domain;
};
```

`lib/traefik-route.nix` builds the router and load-balancer pair. It targets
`http://127.0.0.1:<port>` — the literal IPv4 loopback, not `localhost`.
`localhost` can resolve to `::1` depending on system resolution order, and a
service with a strict reverse-proxy trust check rejects the request outright if
the proxy connects over `::1`. Home Assistant, whose `trusted_proxies` lists only
`127.0.0.1`, returned 400 in exactly this way while AdGuard's route (which has no
such check) worked.

When the target service's own listen port is itself a configurable option (rather than fixed, like dump1090's), pass the live option value — `port = config.services.<foo>.port;` — not a literal, or the route silently decouples the moment anything overrides it. `modules/dns.nix`'s AdGuard route does this, which is why `reliant` moving that port needed no change here.

## Dedicated Bind IPs For LAN-Emulation Services

A service that emulates a whole LAN device needs an address separate from the host's. Add it as a systemd unit — see `bambuddy-bind-ip` in `hosts/reliant/configuration.nix` — never `networking.interfaces.<if>.ipv4.addresses`: that disables DHCP unless `useDHCP = true` too, and can't set `preferred_lft 0`, without which a second address in the same `/24` steals source-address selection from the primary. Pick an address outside the DHCP pool.

## Authelia Forward-Auth (lldap + Authelia SSO)

`custom.lldap` (`modules/lldap.nix`) and `custom.authelia` (`modules/authelia.nix`)
add web-app single sign-on in front of Traefik, for whichever internal admin
UIs opt in. Windows machine-login unification is explicitly out of scope (a
Samba AD domain controller was considered and rejected as too operationally
heavy; pGina rejected as poorly maintained) — this is web SSO only. Linux
machine-login unification via lldap+sssd is viable (lldap ships an official
PAM/sssd example using the posixAccount/posixGroup schema) but is a distinct,
separate future item, not built here — nothing above precludes adding it
later.

- **lldap** (`custom.lldap`) is the directory backend, chosen over Samba AD or
  OpenLDAP for its simpler admin UX and its upstream `bootstrap.sh` script
  (`lldap/lldap`'s own `scripts/bootstrap.sh`, documented in
  `example_configs/bootstrap/bootstrap.md`), which declaratively reconciles
  users/groups from JSON config against lldap's GraphQL API on every run.
  `modules/lldap.nix` renders `custom.lldap.bootstrap.users`/`.groups` to JSON
  files at build time (`pkgs.linkFarm`) and runs the script as a systemd
  oneshot (`lldap-bootstrap.service`) that reruns whenever that generated
  config — or the pinned script itself — changes. `custom.lldap.bootstrap.cleanup`
  (`DO_CLEANUP`) makes those lists the actual source of truth rather than a
  one-time seed: anything not declared gets pruned. Passwords ARE settable
  declaratively via a user's `passwordFile` (bootstrap.sh's real
  `password_file` JSON field) — used here for Authelia's own LDAP bind
  account, so no manual step is needed for that one. Real household accounts
  are a **documented TODO**, not fabricated — see
  `hosts/reliant/README.md` § lldap.
  - `bootstrap.sh` is pinned to the exact lldap release `pkgs.lldap.version`
    already builds (`pkgs.fetchurl` against that tag, not `main`, which would
    drift the script out from under whatever lldap version is actually
    running). If nixpkgs bumps lldap, this hash needs bumping too — `fetchurl`
    fails loudly rather than silently running a mismatched script.
  - Known non-blocking upstream caveat: lldap/lldap#745 reports possible
    duplicate group memberships across repeated bootstrap runs with
    `DO_CLEANUP` on. Not confirmed present in this repo's pinned lldap
    version — watch `journalctl -u lldap-bootstrap` across a few real reruns
    rather than designing around it preemptively.
- **Authelia** (`custom.authelia`) is the Traefik forward-auth portal, backed
  by lldap via LDAP (`authentication_backend.ldap.implementation = "lldap"`).
  2FA scope is **TOTP and WebAuthn only** — Duo is explicitly deferred, no
  `duo_api` config exists. Authelia's bind account
  (`custom.authelia.ldap.bindDn`, default
  `uid=authelia,ou=people,${custom.lldap.baseDn}`) belongs to lldap's built-in
  `lldap_strict_readonly` group, never `lldap_admin` — Authelia only ever
  needs to read user/group attributes, not administer lldap itself.
  - The LDAP bind password is the one Authelia secret that isn't one of
    nixpkgs' `services.authelia.instances.<name>.secrets.*` fields (those
    cover JWT/OIDC/session/storage only) — it goes through Authelia's own
    `AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD_FILE` environment-variable
    secret convention instead (confirmed against Authelia's own secrets
    documentation). Because this is a raw environment variable, not one of
    the `secrets.*` fields that go through systemd's `LoadCredential`, the
    file itself has to be directly readable by the `authelia-main` system
    user (nixpkgs' instance-name-derived user for
    `services.authelia.instances.main`) — the agenix secret's `owner` needs
    to be set to that, not root.
  - Password-reset/identity-verification emails go over real SMTP
    (`custom.authelia.notifier.smtp`) via Brevo's transactional relay when
    enabled; otherwise Authelia falls back to `notifier.filesystem` (writes
    to a local file, dev/test only).
  - Session storage is the in-memory provider (no Redis) — sessions don't
    survive an Authelia restart. Acceptable for this deployment's scale; a
    Redis-backed session store is a future option if that becomes annoying.

### The forward-auth middleware and opting a route in

`modules/authelia.nix` defines exactly one Traefik middleware,
`authelia@file` (Traefik's own `<name>@<provider>` reference syntax for
anything declared through `dynamicConfigOptions`, not a literal filename):

```nix
services.traefik.dynamicConfigOptions.http.middlewares.authelia.forwardAuth = {
  address = "http://127.0.0.1:9091/api/authz/forward-auth";
  trustForwardHeader = true;
  authResponseHeaders = ["Remote-User" "Remote-Groups" "Remote-Email" "Remote-Name"];
};
```

"Gated" here means a Traefik-layer forward-auth check only — it does not by
itself give the backend app any awareness of who logged in. `forwardAuth`
does forward `Remote-User`/`Remote-Groups`/`Remote-Email`/`Remote-Name`
response headers to the proxied app, so an app that's been taught to trust
and read them (from a proxy it's configured to trust) can skip its own login
entirely — but none of the apps this middleware currently sits in front of
have a login of their own to begin with, so that distinction doesn't come up
for them yet. It's exactly why Home Assistant isn't on this list at all: see
below for why forward-auth is the wrong tool for a service with a real
login, and OIDC is the actual answer there.

A route opts in by adding `middlewares = ["authelia@file"]` to its own
router. `lib/traefik-route.nix` grew an optional `middlewares` parameter for
exactly this (empty by default — most routes still carry no auth middleware
at all):

```nix
services.traefik.dynamicConfigOptions.http = mkTraefikRoute {
  name = "adguard";
  # ...
  middlewares = optional (config.custom.authelia.enable && builtins.elem cfg.adminSubdomain config.custom.authelia.protectedSubdomains) "authelia@file";
};
```

A manually-defined router (the `dns2`/`jellyfin`/DCS-control shape, § Second
DNS Instance below) just adds the key directly, the same way `dns2` does on
`reliant` today.

`custom.authelia.protectedSubdomains` is the single list that drives both
sides: it becomes Authelia's own `access_control` rules (`two_factor` policy,
`default_policy = "deny"`) **and** documents which routes are expected to
carry the middleware — but adding a subdomain to that list does not, by
itself, protect anything; the router still has to add
`middlewares = ["authelia@file"]` itself. On `reliant` today that's `dns1`
(this host's own AdGuard admin UI, gated from `modules/dns.nix`), `dns2`
(excelsior's AdGuard admin UI, gated from the manual router in
`hosts/reliant/configuration.nix`), `zigbee.coppertop.ca` (Zigbee2MQTT),
`dcs.coppertop.ca`/`dcs-control.coppertop.ca` (excelsior's DCS webtop
desktop and start/stop control page — **not** the `dcs-control` `/hooks`
webhook router, which is machine-to-machine and would break behind a login
page), `bambuddy.coppertop.ca`, and `rip.coppertop.ca`/`library.coppertop.ca`
(excelsior's ARM and tinyMediaManager admin UIs).

Zigbee and Bambuddy self-register their routers in `modules/zigbee.nix`
and `modules/bambuddy.nix`; rather than edit those files, `reliant`'s
`configuration.nix` layers `middlewares = ["authelia@file"]` onto their
existing entries via Traefik's freeform deep-merge (same mechanism `dns2`
uses). That's the pattern for gating a cross-domain route without editing
its owning module. `rip`/`library` are manually-defined routers (the
`dns2` shape), so they just carry `middlewares` directly.

`home.coppertop.ca` (Home Assistant) is deliberately **not** on this list.
Forward-auth is the wrong mechanism for a service that already has its own
real login — gating it this way adds a redundant second login, not SSO.
Real SSO for Home Assistant is built as a distinct piece of functionality,
Authelia running as an OpenID Connect 1.0 provider — see § OIDC Provider
below — not as a variant of `protectedSubdomains`.

### OIDC Provider

Authelia can run as an OpenID Connect 1.0 provider from the same instance
that serves the forward-auth portal above — both capabilities coexist on
`services.authelia.instances.main`, gated independently
(`custom.authelia.protectedSubdomains` vs `custom.authelia.oidc.enable`).
This is the mechanism for giving a service **with its own real login** actual
SSO, instead of the redundant-second-login problem forward-auth would create
for it. Today the only registered client is Home Assistant, via the
third-party [`hass-oidc-auth`](https://github.com/christiaangoossens/hass-oidc-auth)
HACS component, following Authelia's own
[Home Assistant OIDC integration guide](https://www.authelia.com/integration/openid-connect/clients/home-assistant/)
(fetched at this repo's pinned Authelia version, `v4.39.20` — matching
`pkgs.authelia`'s pin in the pinned `nixpkgs` revision — not guessed).

`custom.authelia.oidc` (`modules/authelia.nix`):

- `enable` turns on `identity_providers.oidc` at all, and requires two new
  secrets:
  - `issuerPrivateKeyFile` — an RSA private key (PKCS#8 or PKCS#1, ≥2048
    bits), Authelia's OIDC issuer signing key. Maps to nixpkgs'
    `services.authelia.instances.<name>.secrets.oidcIssuerPrivateKeyFile`,
    which the nixpkgs module auto-templates into
    `identity_providers.oidc.jwks` at startup (its own Go-template config
    filter, `X_AUTHELIA_CONFIG_FILTERS=template`, enabled automatically the
    moment this secret is set) — `jwks` is never written directly in this
    module's `settings`.
  - `hmacSecretFile` — a random ≥64-character string, Authelia's OIDC HMAC
    secret (`identity_providers.oidc.hmac_secret`), used to sign OIDC JWTs.
    Maps to `secrets.oidcHmacSecretFile`.
- `homeAssistant.enable` registers Home Assistant as an OIDC client
  (asserted to require `oidc.enable`). `clientId` (default
  `home-assistant`) and `redirectUri` (default
  `https://home.${domain}/auth/oidc/callback`, matching
  `modules/home-assistant.nix`'s hardcoded `"home"` subdomain and
  `hass-oidc-auth`'s fixed callback path) both have real, usable defaults —
  only `clientSecretHashFile` needs a value.
- `homeAssistant.clientSecretHashFile` — the one part of this that isn't a
  plain "point at an agenix path" secret. Authelia's
  `identity_providers.oidc.clients[].client_secret` field stores a
  **pbkdf2-sha512 hash** of the shared secret, not the raw secret — there is
  no `oidcClientSecretFile` in nixpkgs' `services.authelia` `secrets.*`
  fields, so this is wired up the same way
  `custom.authelia.ldap.bindPasswordFile` already is: read directly at
  runtime rather than through systemd `LoadCredential`. Concretely, the
  entire Home Assistant OIDC client entry (client ID, redirect URI, scopes,
  `client_secret` included) is rendered as one generated `settingsFile`,
  with `client_secret` substituted in via Authelia's own Go-template `secret`
  function reading the agenix path directly
  (`{{ secret "/run/agenix/..." | mindent 12 "|" | msquote }}`, no manual
  surrounding quotes — `msquote` already produces a correctly-quoted YAML
  scalar). It has to be the *whole* client entry in one file, not split
  across `settings` and a secret fragment, because Authelia's config-file
  merging replaces whole list values (`identity_providers.oidc.clients` is a
  list) rather than merging list items.

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

What this module does **not** cover: Home Assistant's own side (installing
the `hass-oidc-auth` HACS component, HA's `auth_oidc` configuration block).
That's `smart-home`'s (`modules/home-assistant.nix`,
`hosts/reliant/home-assistant/`). The values it needs from this side:

| What HA needs | Value |
| --- | --- |
| OIDC issuer / discovery URL | `https://auth.coppertop.ca/.well-known/openid-configuration` (Authelia's own portal subdomain, `custom.authelia.subdomain`) |
| `client_id` | `home-assistant` (`custom.authelia.oidc.homeAssistant.clientId`) |
| `client_secret` | The **raw** (pre-hash) secret from generating `oidc-client-secret-home-assistant-hash` above — not the agenix path, and not the hash stored there. HA's own config needs the plaintext value; Authelia stores only the digest. |
| Redirect URI | `https://home.coppertop.ca/auth/oidc/callback` (`custom.authelia.oidc.homeAssistant.redirectUri`) — `hass-oidc-auth`'s fixed callback path |
| Authorization/token/userinfo endpoints | Not hardcoded anywhere — `hass-oidc-auth` discovers them from the discovery URL above, per Authelia's OpenID Connect 1.0 Discoverable Endpoints (`/api/oidc/authorization`, `/api/oidc/token`, `/api/oidc/userinfo` under `auth.coppertop.ca`) |

### Self-Lockout Rule

Neither lldap's own admin UI route (`ad.coppertop.ca`) nor Authelia's own
portal route (`auth.coppertop.ca`) may ever carry the `authelia` middleware.
Authelia authenticates against lldap — gating either of those two routes
behind Authelia risks a total lockout the moment lldap is down, mid-bootstrap,
or misconfigured, with no way back in short of console/SSH access to disable
the middleware by hand. Both instead rely on their own native login (lldap's
built-in auth; Authelia's own login form) plus network-level scoping (both
are Traefik-proxied at `127.0.0.1` like every other service here, with no
extra exposure). `modules/authelia.nix` asserts on this directly:
`custom.authelia.protectedSubdomains` may not contain `custom.lldap.subdomain`
or `custom.authelia.subdomain` itself.

## Second DNS Instance (excelsior)

AdGuard Home has no native clustering — every real-world HA setup for it is a
DIY workaround (dual independent instances, or one instance behind a
keepalived VIP with no config sync either way). This repo runs **dual
independent instances**: `reliant`'s existing one, plus a second, fully
separate `custom.dns` on `excelsior`. Neither shares config or state with the
other — router/DHCP should hand out both reserved IPs as primary/secondary
DNS for real redundancy; that's a router-side step, not managed by this repo.

Both admin UIs are reachable without an SSH tunnel, proxied through Traefik:

- `dns1.coppertop.ca` → the host's own AdGuard UI, self-registered by
  `modules/dns.nix` the normal way (§ Traefik Route Registration above), with
  `custom.dns.adminSubdomain = "dns1";` overriding the module's `"dns"`
  default now that a second instance exists to disambiguate from.
- `dns2.coppertop.ca` → `excelsior`'s AdGuard UI. This **cannot** use the
  module's self-registration, which only ever targets `127.0.0.1` — Traefik
  runs on a different host than the service it's proxying. Instead, the
  Traefik host's `configuration.nix` defines this router by hand, pointing
  `lib/traefik-route.nix`'s pattern at `excelsior`'s real LAN IP:

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

  This merges fine alongside every module-contributed route on that host
  since `dynamicConfigOptions` is a TOML freeform type.

`excelsior`'s AdGuard admin UI (`services.adguardhome`, default port 3000) is
bound to `excelsior`'s own LAN IP and reachable only from `reliant`:
`modules/dns.nix` sets `openFirewall = false` (the nixpkgs AdGuard module's
`openFirewall` opens the admin port with no source restriction at all — not
appropriate for a service with weak default auth), and
`hosts/excelsior/configuration.nix` instead adds a `firewall.extraCommands`
rule scoped to `reliant`'s IP (`192.168.20.15`) for that port. `defiant` and
`reliant` need no such rule for their own AdGuard instances — Traefik reaches
those over `127.0.0.1` regardless of the firewall.

`reliant` is the only host carrying this manual `dns2` router and running
Traefik — the "Traefik never runs a second copy" invariant this section
otherwise assumes.

## DCS On-Demand Start/Stop And Remote Control (excelsior)

`excelsior` also runs `custom.dcsServer` (DCS World dedicated server —
`docs/architecture.md` § Custom Options). Two related but distinct things
are proxied here: an on-demand start/stop control page at
`dcs-control.coppertop.ca` (proxied by Traefik, works remotely), and DCS's
own WebGUI (does **not** work remotely through any proxy, by DCS's own
design — see below). The webtop desktop itself — the thing actually used
day-to-day — gets the bare `dcs.coppertop.ca` name; see § DCS's webtop
desktop is proxied cross-host below.

### On-demand start/stop

DCS runs 24/7 by default, which is real resource cost for a game server
that's idle most of the time. `custom.dcsServer.startAtBoot = false;` on
`excelsior` stops the container from auto-starting on boot — the
`podman-dcs-server.service`/`podman-dcs-srs-server.service` systemd units
still exist and can be started on demand, they just don't come back on
their own. `custom.dcsServer.control.enable = true;` stands up the on-demand
surface: a static status/Start/Stop page (nginx) plus a narrowly-scoped
`webhook` (adnanh/webhook) instance that actually runs `systemctl
start`/`stop` on those two units, both bound to excelsior's LAN IP and
firewall-restricted to `reliant` only.

The webhook process itself runs as a dedicated unprivileged `dcs-control`
user, not root. `security.sudo.extraRules` grants that user a `NOPASSWD`
rule scoped to the *exact* two `systemctl start`/`stop` command lines for
those two named units — nothing broader. Stopping is intentionally
**manual only**; there's no idle-timeout auto-stop, since a false-idle read
stopping a live session is worse than the resource cost of a forgotten
manual stop.

`reliant`'s `configuration.nix` proxies `dcs-control.coppertop.ca` at this
control page/webhook, same manual-router shape as `dns2`:

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

Both routers need explicit priorities: `dcsControlPage`'s rule
(`Host(...)`) is a substring of `dcsControlHooks`'s rule
(`Host(...) && PathPrefix(/hooks)`), and Traefik's default rule-length-based
priority for the unprefixed page router beat a previous hardcoded priority
on the hooks router alone, silently routing `/hooks/*` to nginx (a raw 404)
instead of the webhook.

`dcs-control.coppertop.ca` itself has no auth beyond the source-IP restriction —
general Traefik auth in front of it is a deliberate follow-up being done
holistically rather than one router at a time. Starting the container via
the control page does **not** by itself load a DCS mission — that's a
separate, unrelated gap (`Mission list is empty, server not started.` in
DCS's own log), not something start/stop fixes.

### Mission upload

The same control page also has a `.miz` file upload form, backed by a third
`webhook` hook, `/hooks/dcs-upload-mission` — an alternative to `scp`-ing a
mission file to the host over SSH. The browser POSTs the file as a raw
(non-multipart) request body with the filename in an `X-Filename` header;
`adnanh/webhook`'s `pass-file-to-command` only pulls file content out of
`source: payload` for parts it can JSON-decode, so a real binary upload has
to go in as `source: raw-request-body` instead (confirmed against
`adnanh/webhook`'s own Go source, not guessed — its multipart handling never
populates the JSON-parameter map for a non-JSON file part).

The unprivileged `dcs-control` user can't write into the DCS install
directly (it's owned by the container's `PUID`/`PGID`, 1000:1000), so
uploads are privilege-separated the same way start/stop are: the webhook
script stages the file and its sanitized-on-the-way-in name under
`/var/lib/dcs-control/uploads`, then hands off to a **fixed,
zero-argument** `sudo` command (`security.sudo.extraRules`, same pattern as
the start/stop grant) that re-sanitizes the staged filename itself — never
trusting that the unprivileged step already made it safe — and `install`s
it into `custom.dcsServer.control.missionsDir` as `1000:1000`. Sudoers can't
safely pattern-match an arbitrary filename on a command line, which is why
the privileged script takes no arguments at all and reads everything itself
from a fixed staging path instead.

Uploading only gets the file onto the host; DCS still won't run it until
it's added to the active mission list through the tunneled webtop's WebGUI
(see `hosts/excelsior/README.md`) — the same manual step required today,
just without needing an SSH tunnel to get the file there in the first
place.

### DCS's own WebGUI does not work through any reverse proxy

`custom.dcsServer.webGuiPort` (default 8088) is DCS's own remote-control
WebGUI backend (`POST /encryptedRequest`, served by `DCS_server.exe`
itself). **Confirmed live and via DCS's own community documentation: this
cannot be reverse-proxied for remote use, by design.** DCS's server
deliberately rejects `/encryptedRequest` calls that don't arrive from a
genuinely local connection — a real security boundary, not a bug. A same-
origin nginx proxy serving the WebGUI's static files with a same-origin
`app.js` patch was built and tested here; every variation (loopback-bound
backend, forced `credentials: "omit"`, forced `Host: 127.0.0.1`) still got
`422 Unprocessable Entity` from DCS itself. See
`hosts/excelsior/README.md` § Known Gotchas for the full investigation —
worth reading in full before attempting this again.

DCS's own remote-control mechanism instead assumes ports 8088 (WebGUI) and
10308 (game) are directly port-forwarded from the WAN to `excelsior`, with
no HTTP-layer proxy in the path — confirmed by DCS's own log
(`Registering HTTP control interface as <public-ip>:8088 (port is assumed
to be open)`). That router-level port-forward is **not** managed by this
repo. `webGuiBindAddress` is bound to `excelsior`'s LAN IP (not loopback,
not Traefik-proxied) specifically so that WAN forward has something to
reach, and `networking.firewall.allowedTCPPorts` opens 8088 broadly, the
same way the game port already is — real remote DCS clients can come from
any public IP, not just `reliant`'s.

### DCS's webtop desktop is proxied cross-host — unlike the WebGUI above

`custom.dcsServer.desktopPort` (default 3000, overridden to 3001 on
`excelsior` — the module default collides with AdGuard's admin UI) is a
[linuxserver.io webtop](https://docs.linuxserver.io/images/docker-webtop/)
noVNC desktop, not the WebGUI's `/encryptedRequest` API above. noVNC is a
plain websocket video/input stream with no origin check, so the limitation
in § DCS's own WebGUI does not apply here — the desktop proxies cross-host
fine. `reliant`'s `configuration.nix` proxies it at `dcs.coppertop.ca` — the
bare name, since this is the desktop actually used day-to-day, with the
start/stop control page (above) moved to the more explicit
`dcs-control.coppertop.ca` — same manual-router shape as `dcs-control`/`dns2`/Jellyfin:

```nix
routers.dcsDesktop = {
  rule = "Host(`dcs.coppertop.ca`)";
  service = "dcsDesktop";
  tls = {};
};
services.dcsDesktop.loadBalancer.servers = [{url = "http://192.168.1.10:3001";}];
```

`custom.dcsServer.desktopBindAddress` is bound to `excelsior`'s LAN IP (not
loopback) and firewall-restricted to `reliant`'s IP only, same posture as
the control page — webtop has weak default auth, and there's no Traefik
middleware in front of it, so the firewall is the only gate. Opening a
browser tab is now enough to reach the DCS launcher/WebGUI *from inside*
the webtop desktop (same-origin there, so DCS's own local-connection check
still passes) — the SSH-tunnel path (`ssh -L 3001:localhost:3001`) still
works too, it's just no longer required.

## Jellyfin (excelsior)

`excelsior` also runs `custom.jellyfin` (`modules/jellyfin.nix`), backed by a
NAS-mounted media library (`hosts/excelsior/media.nix`). Unlike its
self-hosted usage (the module registers its own Traefik route when
`custom.traefik.enable` is set on the same host — see § Traefik Route
Registration), `excelsior` runs no Traefik of its own: `reliant`'s Traefik
proxies it cross-host, `jellyfin.coppertop.ca` → `excelsior:8096`, the same
manual-router pattern as `dns2` and the DCS control page above:

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

Jellyfin has its own real account system, unlike AdGuard's admin UI or the
DCS control page, so there's no Traefik auth concern here. The port is still
closed off at the network layer the same way as those two: `custom.jellyfin.openFirewall = false;`
on `excelsior`, plus a `networking.firewall.extraCommands` rule scoped to
`reliant`'s reserved LAN IP (`192.168.20.15`) admitting only that host on
port 8096 — matching the `reliantIp` restriction already used for the DCS
control page and AdGuard admin UI in the same file.

## Dynamic DNS

`custom.ddns` (`modules/ddns.nix`) runs `ddclient` to keep `coppertop.ca`'s
apex A record pointed at this residential connection's current public IP —
this ISP has no static IP. It updates only that one record: this zone's
`*.coppertop.ca` is already a CNAME to the apex (confirmed live in the
Cloudflare dashboard, not assumed), so every subdomain follows the apex
automatically without a separate update of its own. That CNAME is managed
by hand in Cloudflare, not by this module — it only needs to exist once.

Since every subdomain rides the same apex update, no Cloudflare change is
needed to add a new subdomain later — this is what lets `excelsior`'s game
servers be reachable by friends over the internet purely by adding a router
port-forward, with no DNS-side follow-up: see `hosts/excelsior/README.md`
§ Services And URLs (`factorio.coppertop.ca`, `dcs.coppertop.ca`) and
§ Provisioning § Optional follow-ups.

It reuses `custom.traefik.acme`'s existing Cloudflare API token
(`traefik/cloudflare-api-token.age`, already granting `Zone:DNS:Edit` /
`Zone:Zone:Read` on this zone for ACME DNS-01) rather than a second secret.
That file is formatted as an `EnvironmentFile=` line
(`CLOUDFLARE_DNS_API_TOKEN=<token>` -- lego's actual env var name for this
provider) for `security.acme`'s consumer, not the bare token ddclient's
`passwordFile` wants, so `modules/ddns.nix` runs the `ddclient` service as
the `traefik` system user (this file's existing owner) and strips the
`CLOUDFLARE_DNS_API_TOKEN=` prefix into a private, owner-only file in its
own runtime directory at service start — see the module for the exact
mechanism and § Known Gotchas below for why this isn't the more obvious
`services.ddclient.passwordFile = apiTokenFile;` one-liner.

### Verifying it worked

- `journalctl -u ddclient -n 50` on `reliant` — a successful run logs the
  Cloudflare zone lookup and, only on an actual IP change, `SUCCESS` for each
  updated record; an unchanged IP logs nothing new by design (`quiet` is
  effectively the default posture for unnecessary updates).
- Force a run and watch it end-to-end:
  `sudo systemctl start ddclient.service && journalctl -u ddclient -f`.
- Query a public resolver directly rather than the LAN's own AdGuard/unbound
  (avoids any doubt about split-horizon DNS in `custom.dns` above, and needs
  no external network to run from): `dig @1.1.1.1 +short coppertop.ca` and
  `dig @1.1.1.1 +short anything.coppertop.ca` should both return this
  network's current public IP — the subdomain query resolves through the
  `*.coppertop.ca` CNAME to the apex, so `dig`'s `+short` output shows the
  apex name on one line followed by the IP. Check the IP against
  `curl -s https://ifconfig.me` run from `reliant` itself.

## Adding A New Homelab Service

1. Write `modules/<service>.nix` exposing `custom.<service>`, following the
   existing modules' shape: `mkEnableOption`, the service config, and a
   `mkIf config.custom.traefik.enable` block registering its route with
   `mkTraefikRoute`.
2. Add it to `modules/default.nix`.
3. Enable it in the host's `configuration.nix` under `custom`.
4. Add its subdomain to `custom.dns.subdomains` so the name resolves on the LAN.
5. If it holds credentials, add an agenix secret — see
   [docs/secrets.md](secrets.md#creating-or-rotating-a-secret) — and reference
   the `/run/agenix/<name>` path from the module option.
6. If it holds state worth keeping, add a `custom.backups.users.<service>` entry
   with explicit `paths`. Verify the real state directory with `ls` on the host
   first; it is not always what the service name suggests.
7. Document the machine-specific facts (URL, first-run wizard, device quirks) in
   that host's README.

If the new service is a Home Assistant integration rather than a standalone
appliance, also see
[docs/smart-home.md § Choosing extraComponents](smart-home.md#choosing-extracomponents)
and the automation-file conventions in that doc.

## Known Gotchas

- `custom.ddns`'s `ddclient` service does not use `services.ddclient.passwordFile`
  pointed straight at `custom.traefik.acme.environmentFile`: that file is an
  `EnvironmentFile=`-format line (`CLOUDFLARE_DNS_API_TOKEN=<token>`), but
  ddclient's `passwordFile` substitutes a file's entire content verbatim as
  the password, so the literal string `CLOUDFLARE_DNS_API_TOKEN=<token>`
  would be sent to Cloudflare as the credential and every update would fail
  auth. `modules/ddns.nix` strips the prefix into a private file at service
  start instead — see § Dynamic DNS above.
- The variable name itself, `CLOUDFLARE_DNS_API_TOKEN`, is lego's actual env
  var for the cloudflare provider — confirmed live against the real secret's
  content (`sudo grep -c '^CLOUDFLARE_DNS_API_TOKEN=' ...` on reliant), not
  assumed from `modules/traefik.nix`'s option description, which previously
  gave the wrong example (`CF_DNS_API_TOKEN`) and broke the first deploy of
  this module's `ExecStartPre` extraction script with a silent "no line
  found" failure — the description is now fixed to match.
- That prefix-stripping step needed `DynamicUser = false` and a fixed
  `User = "traefik"` on `ddclient.service`: with `DynamicUser` (the module's
  default), the service gets a fresh, unpredictable UID per invocation, and
  the ExecStartPre step both reading the real secret and writing the derived
  one would have had to hand that unknown UID access to files it doesn't own.
  Fixing the service to the `traefik` user (already the secret's owner) lets
  every step in the chain run as the same known identity instead.
- ddclient's `cloudflare` protocol only `PATCH`es a DNS record that already
  exists at Cloudflare, of the same type it's expecting — it never creates
  one. `custom.ddns` deliberately lists only the apex in `services.ddclient.domains`,
  not `*.coppertop.ca`: that name is a CNAME in this zone, not an A record,
  and pointing ddclient at it would fail every run with `no 'A' record at
  Cloudflare` (confirmed against ddclient's own source, `nic_cloudflare_update`
  in `ddclient.in` — not guessed) since no A record of that name exists to
  match. The wildcard CNAME still needs to exist in the zone for subdomains
  to resolve at all — it's just not something ddclient itself touches.
- `custom.ddns` sets `usev6 = ""` deliberately, overriding the
  `services.ddclient` module's default (which probes for and reports an IPv6
  address). This zone tracks IPv4 only; leaving `usev6` at its default
  produces a spurious `no 'AAAA' record at Cloudflare` failure every interval
  for a record this setup was never asked to manage.
- `lib/traefik-route.nix`'s new `middlewares` parameter and
  `modules/authelia.nix`'s forward-auth middleware definition both write to
  the same `services.traefik.dynamicConfigOptions.http` option — writing both
  from a single attrset literal inside one module is a plain Nix "attribute
  already defined" error, not a module-system merge conflict. Splitting the
  middleware definition and the route registration into two separate
  `mkMerge` list elements (each its own `mkIf config.custom.traefik.enable
  {...}`) fixes it: the module system already merges independent
  contributions to the same freeform option across separate config
  fragments, which is exactly how `dns.nix`/`home-assistant.nix`/`zigbee.nix`
  already coexist on that option — the fix is keeping every logically
  distinct contribution to it in its own `mkMerge` element, even within a
  single module, not just across modules.
- `authentication_backend.ldap.password` (Authelia's LDAP bind password) is
  not one of nixpkgs' `services.authelia.instances.<name>.secrets.*` fields —
  those only cover JWT/OIDC/session/storage. It has to go through Authelia's
  own environment-variable secrets convention instead
  (`environmentVariables.AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD_FILE`),
  confirmed against Authelia's own secrets documentation
  (`docs/content/configuration/methods/secrets.md` in `authelia/authelia`),
  not guessed from the field name. Because that path bypasses systemd's
  `LoadCredential` (unlike the `secrets.*` fields, which nixpkgs' own
  `services.authelia` module wires through `LoadCredential` automatically),
  the secret file itself must be directly readable by the `authelia-main`
  system user — the agenix `owner` for that one secret needs to be
  `authelia-main`, not root or another service's user.
- This entire lldap/Authelia design was written and reviewed without a
  working `nix build` in the authoring environment (`reliant` is
  `x86_64-linux`; the authoring environment had no `nix` binary at all,
  aarch64 or otherwise) — every config field, secret env var, and script
  interface above was checked against the real pinned nixpkgs modules
  (`nixos/modules/services/databases/lldap.nix`,
  `nixos/modules/services/security/authelia.nix` at this repo's pinned
  `nixpkgs` revision) and upstream `lldap`/Authelia source and docs, not
  guessed, but the actual `nixos-rebuild switch`/`nix build` on `reliant`
  itself was still the first real test of whether it all fits together —
  see the two entries below for what that first real deploy found.
- **Confirmed on the real first deploy**: `modules/lldap.nix`'s rewrite for
  `reliant` (after `defiant`'s decommission) had dropped the static `lldap`
  system user the original version declared, leaving `services.lldap` on
  its default `DynamicUser`. `hosts/reliant/secrets.nix` still set
  `owner = "lldap"` on two agenix secrets, and a real switch failed
  activation outright with `chown: invalid user: 'lldap:0'` — agenix chowns
  secrets to a named user during activation, before any systemd unit (and
  therefore before a `DynamicUser`'s transient UID) exists. Fixed by
  restoring the static user/group and forcing `DynamicUser = false`.
- **Also confirmed live**: `authelia-main.service` only depended on
  `lldap.service` being up, not on `lldap-bootstrap.service` having
  actually finished reconciling the `authelia` bind account into lldap.
  On the real first deploy this raced and crash-looped twice —
  `connection refused` while lldap was still starting, then
  `LDAP Result Code 49 "Invalid Credentials"` while `bootstrap.sh` was
  still mid-run creating that very account — before systemd's
  `Restart=on-failure` got it up on the third attempt. `modules/authelia.nix`
  now blocks `authelia-main.service` on `lldap-bootstrap.service`
  explicitly (a `Type = oneshot` unit that only reports done once
  `bootstrap.sh` actually exits) instead of relying on the restart policy
  to paper over the race.
