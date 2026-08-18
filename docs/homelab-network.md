# Homelab Networking

Reverse proxy and DNS composition for the homelab server — the routing
backbone every other homelab service registers into. The appliance/device
layer that sits behind it (Home Assistant, Zigbee, Z-Wave, Matter, MQTT,
ADS-B) is [docs/smart-home.md](smart-home.md). `custom.dns` also runs a
second, independent instance on `excelsior` — see § Second DNS Instance
(excelsior) below.

## Migration: defiant → reliant

`defiant` (Raspberry Pi 4) is being retired in favor of `reliant` (Gigabyte
Brix x86_64 mini PC, `192.168.20.15`), per `docs/provisioning.md` § Two
Phases. This is a two-step move:

- **Phase 2 (done, this doc's current state)**: `reliant` runs its own,
  fully parallel `custom.dns` + `custom.traefik` instance on its own LAN IP,
  landed in the same PR as `smart-home`'s appliance-layer migration (both
  target this one host as a single coordinated migration, not two
  independent changes). `defiant`'s instances keep running untouched —
  nothing was removed from `hosts/defiant/configuration.nix`. The two hosts
  do not share state; they're independent stacks that happen to be
  configured the same way, the same relationship `excelsior`'s dns2 instance
  already has to `defiant`.
- **Cutover (done, live)**: the LAN's DHCP-advertised DNS server was
  repointed at `reliant`'s own IP (`192.168.20.15`) directly in Unifi —
  **not** by reassigning the `192.168.20.10` reservation, the mechanism
  originally sketched here. `defiant` keeps its `192.168.20.10` reservation
  and keeps running its own DNS/Traefik/appliance stack untouched; clients
  now just aren't told to use it. `192.168.20.15` is `reliant`'s permanent
  LAN IP, not a placeholder pending reassignment — nothing else needs to
  change for cutover to be complete from the network's point of view.
  Removing `custom.dns`/`custom.traefik` (and the rest of the
  homelab/smart-home stack) from `hosts/defiant/` and retiring the Pi is
  still a separate, later step; tracked separately.

`reliant`'s `custom.dns.subdomains` carries `defiant`'s full list —
`home`/`adsb`/`zigbee` included, not just `dns1`/`dns2` — since the
appliance service modules backing those three are enabled in the same PR
(see docs/smart-home.md). Both hosts' `custom.dns.adminSubdomain = "dns1"`
and `custom.dns.lanSubnet = "192.168.0.0/16"` overrides (see below) are
carried identically.

`reliant`'s ACME/DNS-01 credential **reuses** the existing
`traefik/cloudflare-api-token` secret rather than a new one — it's just an
API credential, not tied to either host's identity. Confirmed live: cert
issuance for both `dns1.coppertop.ca` and `zigbee.coppertop.ca` succeeded
(real Let's Encrypt `*.coppertop.ca` wildcard cert, valid chain) once
`reliant` was rekeyed as a recipient.

The full option-to-module table is
[docs/architecture.md § Custom Options § Homelab services](architecture.md#homelab-services) —
that catalogue is canonical for every `custom.*` option in the repo.

## Reverse Proxy And DNS

The two compose to give every service a real HTTPS name on the LAN.

`custom.traefik` requests a **wildcard** certificate for `*.<domain>` using a
DNS-01 challenge, so no service is ever exposed to the internet for validation.
The provider credentials come from an agenix secret via
`acme.environmentFile` (for Cloudflare, a file containing
`CF_DNS_API_TOKEN=...`).

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

`mkTraefikRoute` also takes an optional `middlewares` list (e.g.
`middlewares = ["authelia"];` — see § Authelia + lldap SSO below) attached to
the generated router. For a route this repo can't add that argument to because
the calling module belongs to another domain (`smart-home`'s
`modules/home-assistant.nix`/`modules/zigbee.nix`), the same effect is layered
on from the host's `configuration.nix` as a data-only overlay — see the
`routers.homeassistant.middlewares`/`routers.zigbee.middlewares` lines in
`hosts/defiant/configuration.nix`, the same pattern § Second DNS Instance's
manual `dns2` router already established for cross-domain data that isn't a
module change. This works because `dynamicConfigOptions.http` is a freeform
TOML type that deep-merges attrsets contributed from multiple files rather
than erroring on "multiple definitions" — confirmed against the real NixOS
`services.traefik` module source (`pkgs.formats.toml{}`'s freeform type),
not assumed.

## Authelia + lldap SSO

`custom.lldap` (`modules/lldap.nix`) and `custom.authelia` (`modules/authelia.nix`)
give the LAN a real directory service and a forward-auth SSO portal in front of
Traefik, for a multi-user household rather than a single login shared across
services.

- **lldap** is the directory backend — a lightweight LDAP server with its own
  web admin UI, chosen over OpenLDAP's `declarativeContents` for that UI, even
  though its NixOS module only lets you declare the *service* (storage, ports,
  initial admin password), not individual accounts.
- **Declarative accounts, closing that gap**: `custom.lldap.users`/`.groups`
  (set per-host, e.g. `hosts/defiant/lldap-accounts.nix`) render to one JSON
  file per account/group under `/etc/lldap-bootstrap/{user,group}-configs/`,
  reconciled against the live server by lldap's own upstream
  `scripts/bootstrap.sh` (git-ops style, via its GraphQL API) on every
  `nixos-rebuild switch` — not just when the JSON content changes, since
  `DO_CLEANUP=true`'s whole point is pruning drift introduced through lldap's
  own UI between rebuilds, which a content-hash-based `restartTrigger` alone
  would miss. The script isn't packaged by nixpkgs (it's an ops script, not
  part of the built binary) — it's pulled straight from the same source tree
  nixpkgs already fetches for the pinned lldap version
  (`${pkgs.lldap.src}/scripts/bootstrap.sh`), so it stays in lockstep with
  whatever version this host actually runs.
- **Passwords are declarative too**: bootstrap.sh's JSON schema accepts a
  `password_file` field per account (confirmed against the real upstream
  `example_configs/bootstrap/bootstrap.md`, not guessed), so the Authelia LDAP
  bind service-account's password can be set the same way as every other
  field — both `custom.lldap.users.authelia.password_file` and
  `custom.authelia.ldap.bindPasswordFile` point at the same agenix secret, no
  manual one-time step needed to keep the two sides of that bind in sync.
- **Authelia** is the forward-auth provider. It self-registers its own portal
  route (`custom.authelia.subdomain`, default `auth`) and a reusable
  `middlewares.authelia.forwardAuth` entry (`address =
  "http://127.0.0.1:9091/api/verify"` — the same loopback-not-`localhost`
  invariant as every other route here). `custom.authelia.protectedSubdomains`
  lists which subdomains get an `access_control` rule (`policy = "two_factor"`);
  each of those subdomains' Traefik router *also* needs
  `middlewares = ["authelia"];` attached separately (see above) — the two are
  independent and both required, or you get either an unprotected route or a
  hard lockout (`access_control`'s `default_policy` is `deny`).
- **2FA**: TOTP and WebAuthn are enabled (Authelia's defaults); Duo is
  deferred, not cancelled — no `duo_api` block or `integration_key`/`secret_key`
  secrets exist yet.
- **Session storage**: the default in-memory provider, not redis — a single
  Authelia instance on one node doesn't need it, at the cost of sessions not
  surviving an `authelia-main` restart (occasional forced re-login).
- **Notifications**: the filesystem notifier (`/var/lib/authelia-main/notification.txt`),
  not SMTP — this repo has no existing mail-sending infrastructure to depend
  on. Password-reset/identity-verification links land in that file, read over
  SSH, rather than being emailed.

**Two self-lockout traps, both handled the same way — leave the route
unprotected, rely on the service's own login plus network scoping instead**:

- Authelia's own portal route must never carry the `authelia` middleware —
  it can't gate access to its own login page.
- lldap's admin UI (`custom.lldap.adminSubdomain`, default `ad`) must never
  carry it either, one hop removed: Authelia authenticates *against* lldap, so
  if lldap is ever down, misconfigured, or mid-bootstrap before any accounts
  exist, gating access to lldap's own UI on Authelia means there's no way to
  reach the tool that would fix it. LAN-only reachability (unbound's
  `access-control`, and later the WireGuard subnet once that exists) is the
  real protection for that route, the same way it already is for lldap's LDAP
  port itself.

`custom.lldap`'s systemd unit runs as a static `lldap` user, not the module's
own `DynamicUser` default — see § Known Gotchas in `hosts/defiant/README.md`.

## Second DNS Instance (excelsior)

AdGuard Home has no native clustering — every real-world HA setup for it is a
DIY workaround (dual independent instances, or one instance behind a
keepalived VIP with no config sync either way). This repo runs **dual
independent instances**: `defiant`'s existing one, plus a second, fully
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

`excelsior`'s AdGuard admin port needs no extra firewall work for this to be
reachable: `services.adguardhome.host` defaults to `0.0.0.0`, and
`modules/dns.nix` already sets `openFirewall = true`.

During the `defiant` → `reliant` migration (§ Migration above), **both**
`defiant` and `reliant` carry this manual `dns2` router and run their own
Traefik instance in parallel — each independently proxies its own `dns1` and
the same `excelsior` `dns2` target. That's a temporary, intentional
duplication: at cutover, `defiant`'s copy of `custom.traefik`/`custom.dns`
(including this manual router) is removed, leaving `reliant` as the only
Traefik instance, matching the eventual "Traefik never runs a second copy"
invariant this section otherwise assumes.

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
