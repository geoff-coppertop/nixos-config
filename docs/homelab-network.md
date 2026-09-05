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

When the target service's own listen port is itself a configurable option
(rather than fixed, like dump1090's), pass the live option value —
`port = config.services.<foo>.port;` — not a literal. `modules/dns.nix`'s own
AdGuard route does this (`config.services.adguardhome.port`, upstream default
3000): a hardcoded `3000` would silently decouple the route from the real port
the moment that option is ever overridden, which is a real prerequisite for
another module on `reliant` — `custom.bambuddy`'s virtual-printer feature
hardcodes ports 3000/3002 upstream and can't be enabled on this host until
AdGuard moves off 3000, see `hosts/reliant/README.md` § Bambuddy.

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
live at `dcs.coppertop.ca`: an on-demand start/stop control page (proxied
by Traefik, works remotely), and DCS's own WebGUI (does **not** work
remotely through any proxy, by DCS's own design — see below).

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

`reliant`'s `configuration.nix` proxies `dcs.coppertop.ca` at this control
page/webhook, same manual-router shape as `dns2`:

```nix
routers.dcsControlHooks = {
  rule = "Host(`dcs.coppertop.ca`) && PathPrefix(`/hooks`)";
  service = "dcsControlHooks";
  priority = 100;
  tls = {};
};
routers.dcsControlPage = {
  rule = "Host(`dcs.coppertop.ca`)";
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

`dcs.coppertop.ca` itself has no auth beyond the source-IP restriction —
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
fine. `reliant`'s `configuration.nix` proxies it at `dcs-desktop.coppertop.ca`,
same manual-router shape as `dcs`/`dns2`/Jellyfin:

```nix
routers.dcsDesktop = {
  rule = "Host(`dcs-desktop.coppertop.ca`)";
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
