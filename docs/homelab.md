# Homelab Networking

Reverse proxy and DNS composition for `defiant` — the routing backbone every
other homelab service registers into. The appliance/device layer that sits
behind it (Home Assistant, Zigbee, Z-Wave, Matter, MQTT, ADS-B) is
[docs/smart-home.md](smart-home.md).

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
