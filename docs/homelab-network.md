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
