# Homelab Services

The reusable service layer under `modules/`. All of it is currently enabled on
`defiant`; machine-specific facts, URLs, and device quirks live in
[hosts/defiant/README.md](../hosts/defiant/README.md).

## Service Module Map

| Option | Module | Provides |
| --- | --- | --- |
| `custom.dns` | `modules/dns.nix` | unbound recursive resolver on 5335 plus AdGuard Home on 53 |
| `custom.traefik` | `modules/traefik.nix` | Reverse proxy, HTTP→HTTPS redirect, ACME wildcard certificate |
| `custom.home-assistant` | `modules/home-assistant.nix` | Home Assistant, `extraComponents`, proxy trust |
| `custom.mqtt` | `modules/mqtt.nix` | Mosquitto broker on 1883 |
| `custom.matter` | `modules/matter.nix` | python-matter-server (`ws://localhost:5580/ws`) |
| `custom.zigbee` | `modules/zigbee.nix` | Zigbee2MQTT, frontend on 8082 |
| `custom.zwave` | `modules/zwave.nix` | Z-Wave JS WebSocket server |
| `custom.adsb` | `modules/adsb.nix` | dump1090 ADS-B receiver, map on 8080 |

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

### Traefik route registration

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

## Home Assistant

The **service** — package, `extraComponents`, HTTP and proxy setup — is
configured by `modules/home-assistant.nix` plus the host's `extraComponents` in
`configuration.nix`. The module sets `configWritable = true`, so UI-created
automations are written to `automations.yaml` alongside the Nix-declared ones.

`sun = {}` is set explicitly in the module: unlike `ssdp` and `zeroconf`, which
are part of HA's always-on core bootstrap, `sun` is never set up unless
referenced, and `sun.sun` does not exist at all without it. It needs no extra
packages, so it is not an `extraComponents` entry.

### Declarative automations

Automations are declared in Nix, **one file per concern**, under
`hosts/<host>/home-assistant/`. A `default.nix` in that directory imports each
concern file, and the host's `configuration.nix` imports the directory
(`./home-assistant`, which resolves to its `default.nix`).

```text
hosts/defiant/home-assistant/
├── default.nix           # imports each concern file below
├── outside-lights.nix    # arrival/departure outside lights
├── door-locks.nix        # nightly door lock
└── presence-lighting.nix # presence-driven office lighting
```

Rules for this layer:

- **One feature-area per file**, named for the concern — not a single catch-all
  automations file, and not a flat `hosts/<host>/home-assistant.nix` (that name
  would collide with the `modules/home-assistant.nix` service module). To add an
  automation, create `hosts/<host>/home-assistant/<concern>.nix` and import it in
  that directory's `default.nix`.
- Each file contributes to `services.home-assistant.config."automation manual"`,
  a list. NixOS merges the lists across files, so the concern files coexist
  without conflict. Use the `"automation manual"` key, **not** bare
  `"automation"`, so Nix-declared automations coexist with UI-created ones.
- A concern file may also hold that concern's related HA config — helpers,
  scripts, template sensors — not just automations.
- This directory holds **only** per-concern automation and config content. The
  service itself belongs in the module and the host configuration.

### Choosing `extraComponents`

HA's `default_config` baseline in nixpkgs is small, and a missing dependency
surfaces as an "Invalid config" notification rather than a clear error. Worse,
`default_config`'s setup can abort partway through on one component's crash,
taking unrelated components down with it — a `conversation` failure
(`ModuleNotFoundError: No module named 'hassil'`) previously took out `met`,
which had been working fine on its own.

When an integration misbehaves, check `journalctl` and nixpkgs'
`component-packages.nix` for what the component actually needs, then add it to
`extraComponents` rather than assuming `default_config` covers it. Note that some
integrations are distinct platforms needing their own entry — `google_translate`
is separate from the core `tts` component, for instance.

## Radio Networks

### Zigbee

`custom.zigbee` runs Zigbee2MQTT against a USB coordinator on
`serialPort` (default `/dev/ttyUSB0`), with the network key read from
`networkKeyFile`. It publishes to the MQTT broker; Home Assistant discovers
entities from `zigbee2mqtt/bridge/...` topics, which is why the `mqtt` component
must be in `extraComponents` — Zigbee2MQTT has no HA component of its own.

### Z-Wave

`custom.zwave` runs the Z-Wave JS WebSocket server against `serialPort` (default
`/dev/ttyACM0`), reading `securityKeys` from `secretsConfigFile`. Home Assistant
connects to it with the `zwave_js` component, which does not ship in the
`default_config` baseline.

`zwave-js-server` does **not** generate `securityKeys` itself. Leaving the
default placeholder crash-loops the service indefinitely. Generate real keys
before first deploy — see
[docs/secrets.md § defiant service secrets](secrets.md#defiant-service-secrets).

The module's default port is 3000, which collides with AdGuard Home's admin UI on
any host running both. Set `port = 3001` (or anything free) in that case.

### Both

Neither radio's key can be rotated cheaply: regenerating the Zigbee network key
or the Z-Wave security keys after devices are paired or included breaks every one
of them and forces a full re-pair. Create both before the first boot and store
them in Bitwarden.

Serial device paths are not stable guesses. Confirm them on the host after first
boot with `ls /dev/tty{ACM,USB}*` before pinning them in the config.

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
