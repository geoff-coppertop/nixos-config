# reliant

This host is the homelab server — it replaced `defiant` (Raspberry Pi 4,
retired) via a migration that landed `custom.dns`/`custom.traefik` (owned by
`homelab-network`, see [docs/homelab-network.md](../../docs/homelab-network.md))
and the appliance layer: Home Assistant, MQTT, Matter, Zigbee, Z-Wave, ADS-B
(owned by `smart-home`, see [docs/smart-home.md](../../docs/smart-home.md))
in one combined PR, since both targeted this same host as a single
coordinated migration rather than two independent changes. `defiant` has
since been fully retired and removed from the flake.

**Live and confirmed working**: the Zigbee and Z-Wave USB radios are
physically moved here and paired devices respond (Zigbee network key and
Z-Wave `securityKeys` reuse worked as intended, no re-pair needed); the ADS-B
receiver is reading real traffic; all four backup jobs run clean; Home
Assistant's config was restored from `defiant`'s restic snapshot (prior to
its retirement) and is controlling real devices; `dns1.coppertop.ca`/
`zigbee.coppertop.ca` resolve and serve valid `*.coppertop.ca` certs through
this host's own Traefik. The LAN's DHCP-advertised DNS server is this host's
own IP (`192.168.20.15`) in Unifi — `reliant` is the DNS primary.

**Still open**: AdGuard's filter/allow/deny-list configuration wasn't part
of the Home Assistant restore and hasn't been migrated — `reliant`'s AdGuard
is a fresh instance; Z-Wave device-level control (beyond the driver being
healthy) not yet spot-checked. Bambuddy and its slicing sidecar are newly
added and have not been run on this hardware yet — see § Bambuddy below.

## Services

`custom.dns` (unbound + AdGuard Home) and `custom.traefik` run on this host's
own reserved LAN IP, `192.168.20.15` — now the LAN's actual DNS primary (see
above). See [docs/homelab-network.md](../../docs/homelab-network.md) for the
full design; host-specific facts:

- `dns1.coppertop.ca` → this host's own AdGuard Home admin UI.
- `dns2.coppertop.ca` → `excelsior`'s AdGuard Home admin UI, proxied
  cross-host by a manual router (see docs/homelab-network.md § Second DNS
  Instance (excelsior)).
- `custom.traefik.acme.environmentFile` points at
  `/run/agenix/traefik/cloudflare-api-token` — **reused** from `defiant`'s
  existing secret (it's just an API credential, not tied to either host's
  identity), not a new one. Confirmed live: cert issuance succeeded.

### Ports

Every port this host binds, in ascending order — the complete list for
`reliant`. It runs the densest service stack in the fleet, and every port
collision this repo has hit has been on this host or its `defiant`
predecessor — so check this table before assigning or moving any port here,
and update it in the same commit
([docs/architecture.md § Placement
Rule](../../docs/architecture.md#placement-rule)).

| Port | Protocol | Purpose | Exposure |
| --- | --- | --- | --- |
| 22 | tcp | SSH, `services.openssh` with `openFirewall = true` | LAN (firewall open); key-only auth, no password/root login |
| 53 | tcp+udp | AdGuard Home resolver, `custom.dns` | Bound `0.0.0.0`; UDP 53 opened to the LAN by `modules/dns.nix` (TCP 53 deliberately not opened) |
| 80, 443 | tcp | Traefik entry points (`web`/`websecure`), `custom.traefik` | LAN/WAN (firewall open) — every proxied service is reached through 443 here, never its own port |
| 322, 990, 2024–2026, 3000, 3002, 6000, 8883, 50000–50029 | tcp | Bambuddy virtual printer — bind/detect, RTSPS camera, FTPS, A1/P1S protocol, file tunnel, MQTT, FTP passive range (sized by `virtualPrinter.count`, 3 here). Ports are hardcoded upstream (`bind_server.py`), and the listeners start once an **enabled** virtual-printer row exists — `custom.bambuddy.virtualPrinters` declares one here | Bound on `192.168.20.40` (the row's `bindIp`), not `0.0.0.0` — `virtual_printer/manager.py` passes `bind_ip` through to every listener. Opened to the LAN by `virtualPrinter.openFirewall`, which is what lets a slicer reach them. Its 3000 no longer collides with AdGuard, which moves to 3004 in this same change; see § Bambuddy |
| 1883 | tcp | Mosquitto MQTT broker, `custom.mqtt` | 127.0.0.1 only |
| 3000 | tcp | AdGuard Home admin UI, `custom.dns` (upstream default) | Bound `0.0.0.0`, `openFirewall = false`; reached through Traefik at `dns1.coppertop.ca` |
| 3001 | tcp | zwave-js websocket, `custom.zwave.port` — overridden here because the module default (3000) is AdGuard's admin UI | Firewall closed; Home Assistant connects over localhost |
| 3001 | tcp | BambuStudio sidecar, `custom.bambuddy.slicerSidecar.bambuStudio.port` (`bambuStudio.enable` off) | **Not bound today** — and its default is the 3001 zwave-js already holds above; `modules/bambuddy.nix` asserts on that pair, so enabling it needs an explicit `port` here first |
| 3003 | tcp | OrcaSlicer slicing sidecar (podman publish), `custom.bambuddy.slicerSidecar.port` | 127.0.0.1 only; called only by Bambuddy on this host |
| 5335 | tcp+udp | unbound recursive resolver, `custom.dns` | LAN (firewall open) — the deliberate AdGuard-bypass |
| 5353 | udp | avahi/mDNS, `profiles/common/networking.nix` (`openFirewall = true`) | LAN (firewall open) — what makes `reliant.local` resolve for deploys |
| 5580 | tcp | python-matter-server websocket, `custom.matter` (upstream default) | Firewall closed; Home Assistant connects over localhost |
| 8000 | tcp | Bambuddy web UI / REST API, `custom.bambuddy.port` | `custom.bambuddy.listenAddress` = 127.0.0.1; Traefik at `bambuddy.coppertop.ca` |
| 8080 | tcp | nginx serving dump1090's skyaware UI and `aircraft.json`, `custom.adsb` (hardcoded) | 127.0.0.1 only; Traefik at `adsb.coppertop.ca` |
| 8082 | tcp | Zigbee2MQTT frontend, `custom.zigbee` (hardcoded in `modules/zigbee.nix`) | Firewall closed; Traefik at `zigbee.coppertop.ca` |
| 8083 | tcp | Homepage dashboard, `custom.homepage` — moved off its upstream default (8082, Zigbee2MQTT's) after a live collision, see Known Gotchas | 127.0.0.1 only; Traefik at the apex, `coppertop.ca` |
| 8123 | tcp | Home Assistant frontend, `custom.home-assistant` (HA's own default; the module's Traefik route hardcodes it) | Opened to `192.168.20.0/24` only by `firewall.extraCommands`, for Sonos UPnP callbacks; everything else goes through Traefik at `home.coppertop.ca` |
| 30001–30005, 30104 | tcp | dump1090's raw/Beast/SBS feed listeners, `custom.adsb` (it runs dump1090 with `--net`, so these are dump1090's own defaults) | Bound `0.0.0.0`, firewall closed |

`custom.backups` and `custom.ddns` bind nothing — both are outbound-only (SMB
to the NAS, HTTPS to Cloudflare).

Provisioning steps are the generic `disko` flow in
[docs/provisioning.md § Provision Types](../../docs/provisioning.md#provision-types)
onward (same as `enterprise-d`/`excelsior`).

## Device Pairing Notes

- **ecobee thermostats (2×, HomeKit)** — `home-assistant/ecobee-climate.nix`
  covers the two zones actually installed today, `climate.main_and_basement`
  and `climate.upstairs`; a garage thermostat and upstairs AC are planned but
  not installed, and will land as their own PRs once that hardware exists
  rather than as unused code now. Unpair from Apple Home first — a HomeKit
  accessory accepts only one controller. The setup code is on the
  thermostat: Menu → Settings → HomeKit. After pairing, rename each climate
  entity to match the file's entity list (or edit that list to match). Set
  each thermostat's hold action to **Until I change it** so its own schedule
  never overrides the automations' setpoint — Home Assistant/HomeKit has no
  way to set this remotely, so it stays a manual per-thermostat step. Switch
  seasons by toggling `input_boolean.climate_summer_mode` in the HA UI — it
  applies immediately, no rebuild needed.
- **Presence (person entities)** — the ecobee automations key off
  `zone.home`, which needs at least one `person` entity with a device
  tracker attached. Install the HA companion app on each phone, then HA →
  Settings → People, attach each phone's device tracker.
- **Apple TV (3×)** — in HA → Integrations, add each Apple TV and complete
  the on-screen/HA PIN pairing. Name each device during pairing as `Apple TV
  Upstairs Living Room`, `Apple TV Basement Living Room`, and `Apple TV
  Geoff's Office` (matching their physical locations) so HA derives
  predictable, clearly scoped entity_ids:
  `media_player.apple_tv_upstairs_living_room`,
  `media_player.apple_tv_basement_living_room`, and
  `media_player.apple_tv_geoff_s_office`.
- **Broadlink RM4 mini (Geoff's Office AV IR blaster)** — in HA → Integrations, add
  it (config-flow, discovers the RM4 automatically on the LAN); it lands as
  `remote.geoff_s_office_wi_fi_universal_remote`. `home-assistant/appletv-av.nix`
  bakes all four commands in as raw `b64:` codes rather than referencing
  device/command names, so nothing here depends on this pairing's live
  `.storage` state — but that only matters again if the projector or the
  receiver is ever physically replaced, since the codes are specific to
  each unit's own remote/protocol, not to this RM4 or this pairing:
  - **Projector replaced**: learn its two commands, one press per command
    aimed at its own remote while the RM4's learn light is on: Developer
    Tools → Actions → `remote.learn_command`, for `device: projector,
    command: PowerOn` and `PowerOff`. Then pull the two codes straight out
    of storage (`ssh <host> sudo cat
    /var/lib/hass/.storage/broadlink_remote_<mac>_codes`) and paste them
    into `epsonPowerliteHomeCinema3020PowerOnCode`/`epsonPowerliteHomeCinema3020PowerOffCode` in the Nix file.
  - **Receiver replaced**: its remote almost certainly won't share this
    exact unit's NEC address/command bytes even if it's another Yamaha —
    see `docs/smart-home.md` § Receiver power for how
    `yamahaHtr4063PowerOnCode`/`yamahaHtr4063PowerOffCode` were derived; the whole
    reverse-engineering exercise has to be redone from scratch for the new
    unit.
  This integration only ever drives receiver/projector *power* — Apple TV
  volume for that same AV chain in Geoff's Office goes through CEC instead (Apple TV
  Settings → Remotes and Devices → Volume Control → Auto), not through this
  integration.

## Bambuddy (3D Printing)

`custom.bambuddy` runs Bambuddy natively (`pkgs/bambuddy.nix` — the upstream
image is not used; see the header comment there for why) plus the OrcaSlicer
slicing sidecar as a podman container. Host-specific notes:

- Reached at `bambuddy.coppertop.ca` through this host's Traefik. The app
  itself binds `127.0.0.1:8000` only, the same posture as every other service
  here.
- **Each printer needs LAN Only Mode + Developer Mode enabled**, on the
  printer: Settings → Network → LAN Only Mode, then Developer Mode (it only
  appears after LAN Only Mode is on). Note the Access Code, IP, and serial —
  those three are what the first-run wizard asks for. Without Developer Mode
  the printer is read-only monitoring at best. Also enable **"Store sent files
  on external storage"** in the slicer, or Bambuddy has no 3MF to archive.
- The slicing sidecar listens on `127.0.0.1:3003` and is called only by
  Bambuddy on this same host — no Traefik route, no firewall opening. Its
  image is **linux/amd64 only** upstream (no ARM64 build, no source for the
  patched OrcaSlicer CLI inside it), which is fine here and would not be on an
  ARM host. `SLICER_API_URL` is set from the module, so nothing needs entering
  in Settings → Slicer.
- **The virtual-printer feature is off at the firewall on this host and cannot
  simply be turned on.** It binds ports 3000/3002 unconditionally — hardcoded
  in upstream's `bind_server.py`, because a slicer looks for a real printer on
  exactly those ports — and 3000 is already AdGuard Home's admin UI here.
  `modules/bambuddy.nix` asserts on that combination rather than letting it
  fail at bind time; moving `services.adguardhome.port` is the prerequisite.
- Data (SQLite database, 3MF/print archive) lives in `/var/lib/bambuddy`,
  owned by a fixed `bambuddy` system user. Logs are in `/var/log/bambuddy`.

### Declarative printers

Bambuddy keeps its printer list and virtual-printer config in that SQLite
database, and it has no seeding mechanism — no seed file, no import path, no
printer-related environment variables (checked in
`backend/app/core/config.py` at v1.2.5.3). So `custom.bambuddy.printers` and
`custom.bambuddy.virtualPrinters` are reconciled into it over Bambuddy's own
REST API by `bambuddy-provision.service`
(`modules/bambuddy-provision.nix`).

- **It only ever creates.** It lists what is already there, adds what is
  missing, and touches nothing else — no updates, no deletions. Changing a
  printer in the web UI is a legitimate thing to do and never gets reverted;
  removing an entry from Nix never destroys a printer row or the print
  history keyed to it. This is a deliberate limit, not an unfinished
  feature — the reasoning is in the script's module docstring.
- **It runs at boot, after every rebuild that changes the declared set, and
  every 15 minutes** (`bambuddy-provision.timer`). The timer is not
  decoration: Bambuddy verifies the MQTT connection to a real printer before
  it will save it, so a printer that is powered off simply cannot be added
  yet — see Known Gotchas.
- Check on it with `systemctl status bambuddy-provision.service`. Exit 75
  means "declared but not reconcilable yet" (printer offline, or an
  access-code secret that does not exist yet); exit 1 means something that
  retrying will not fix. The journal names the printer either way.
- Access codes are never in the repo. Each entry points at a file
  (`accessCodeFile`) that agenix decrypts to `/run/agenix/...`, read at
  provisioning time by a root unit — declare the secret with no `owner`, as
  with this host's other root-read secrets.

The virtual printer declared here is `Bambuddy`, in **queue** mode: a slicer
sends a job to it, the job lands in Bambuddy's print queue, and
`auto_dispatch` sends it on to a real printer. It binds `192.168.20.40`, a
secondary address on `enp3s0` added separately (PR #164) so the virtual
printer's hardcoded ports do not have to share the primary address with
AdGuard and friends.

**It is not reachable from the LAN yet**, and the module says so at eval time
with a warning. `virtualPrinter.openFirewall` is off (it cannot be turned on
while AdGuard holds 3000), so the firewall drops every slicer connection to
those ports. Enabling it needs AdGuard's admin UI moved off 3000 first. It
also needs `/run/agenix/bambuddy/virtual-printer-access-code` to exist —
until then provisioning reports it pending on every tick and creates nothing.

The real P2S is **not** declared here yet: it was added by hand before this
existed, so provisioning finds it by serial and leaves it alone, and its LAN
IP has not been confirmed for the repo. Declaring it makes the config match
reality and survives a rebuild from scratch:

```nix
custom.bambuddy.printers = [
  {
    name = "P2S";
    serialNumber = "<the printer's serial>";
    ipAddress = "<its LAN IP>";
    accessCodeFile = "/run/agenix/bambuddy/p2s-access-code";
    model = "P2S";
  }
];
```

That needs a `secrets/bambuddy/p2s-access-code.age` from `secrets-warden`
holding the printer's LAN Access Code, and the matching `age.secrets` entry
in `hosts/reliant/secrets.nix`.

## Machine Files

| File | Purpose |
| --- | --- |
| `configuration.nix` | Boot, hardware, networking, `custom.users`, `custom.backups`, (Phase 2) `custom.dns`/`custom.traefik`/`custom.home-assistant`/`mqtt`/`matter`/`zigbee`/`zwave`/`adsb` all migrated from `defiant`, plus `custom.bambuddy` (new here) |
| `hardware.nix` | systemd-boot, EFI, Intel microcode, generic firmware (template, not a hardware scan — see Hardware And Access below) |
| `power.nix` | Explicit no-hibernate/no-suspend statement for this always-on headless host |
| `disko.nix` | GPT layout: ESP, swap, plain ext4 root (no btrfs/snapper — see the comment in the file for why) |
| `default.nix` | Imports `configuration.nix` and attaches `thomasga`'s home-manager config (`./home/thomasga.nix`) |
| `secrets.nix` | `age.secrets` declarations for this host, including the Phase 2 smart-home entries — see § Secrets below |
| `home-assistant/` | Declarative HA automations, one file per concern — mostly a copy of `hosts/defiant/home-assistant/`, plus `ecobee-climate.nix` and `bambuddy-printers.nix` (new here, not migrated) |
| `provision-type` | `disko` |

## Hardware And Access

- Gigabyte GB-BXi5-4200 "Brix" mini PC — Intel Core i5-4200U (Haswell),
  8GB DDR3L RAM (single Kingston SODIMM installed, second slot empty),
  Crucial M500 120GB mSATA SSD. USB3, gigabit LAN, HDMI.
- No TPM2 confirmed on this hardware — `disko.nix` uses no LUKS/TPM, unlike
  `enterprise-d`. Do not adopt that host's LUKS+TPM pattern here without
  confirming a TPM2 chip is actually present.
- The disk is expected to enumerate as `/dev/sda` (SATA/mSATA, not NVMe) —
  `disko.nix`'s default matches that, but **verify with `lsblk` at install
  time** (Step 5) before confirming the target device; disko destroys
  whatever it's pointed at.
- `hardware.nix` is a best-effort template mirroring `excelsior`'s shape
  (systemd-boot, EFI, redistributable firmware, Intel microcode) — it is
  **not** a `nixos-generate-config` scan, since this machine has not been
  physically installed yet. Verify against the installer's own hardware
  detection during Step 5 and correct here if the Brix needs anything this
  omits.
- Reserved LAN IP `192.168.20.15`, set as a DHCP reservation in Unifi —
  distinct from `defiant`'s own reservation (`192.168.20.10`, which stays
  with `defiant` — cutover repointed Unifi's DHCP-advertised DNS server at
  this IP directly rather than reassigning `defiant`'s reservation).
  Consumed by `custom.dns.lanIp` — see § Services above.
- Headless. `profiles/desktop` is deliberately **not** imported — there is no
  display server. `profiles/dev` is also not imported — the appliance
  service set migrated in this PR (Home Assistant, Zigbee2MQTT, Z-Wave JS,
  etc.) doesn't need it.
- Zigbee coordinator (`/dev/ttyUSB0`, vendor ID `0658`) and Z-Wave controller
  (`/dev/ttyACM0`, vendor ID `10c4`) are passed through by the same
  `udev.extraRules` entry `defiant` uses, into the `dialout` group;
  `thomasga` is in that group here too. Confirmed live: both dongles are
  physically moved here and paired devices respond without a re-pair.
- SSH key only: `PasswordAuthentication`, `KbdInteractiveAuthentication`, and
  `PermitRootLogin` are all off.
- `security.sudo.wheelNeedsPassword = false`, same reasoning as `defiant` and
  `excelsior`: the authorized-key check is the real access gate, and a sudo
  password on top of it only blocks unattended `nixos-rebuild --target-host`
  deploys.
- The bare `reliant` hostname isn't resolvable — use the mDNS `.local` name
  for deploys regardless of DNS cutover status:

  ```bash
  nixos-rebuild switch --flake .#reliant --target-host thomasga@reliant.local --sudo
  ```

## Disk Layout And GC Tuning

- `disko.nix`: GPT with a 1G ESP, 4G swap, and the rest as a plain ext4 root
  (no LVM). ext4, not `excelsior`'s btrfs-with-subvolumes pattern — that
  pattern exists there to keep a large, fast-growing DCS install out of
  snapper's timeline snapshots on a 1TB disk with headroom to spare. This
  disk is 120GB total, smaller than that DCS install alone, and Phase 2 is
  expected to migrate `defiant`'s growing homelab state onto it. Adding
  btrfs CoW + snapper snapshots on top of that here risks the kind of
  disk-pressure problem `defiant`'s fixed-size SD card hit (see
  git history, since that host and its README are now retired). Plain ext4
  avoids that; btrfs + snapper can be added later if there turns out to be
  headroom to spare.
- `hardware.nix`'s `boot.loader.systemd-boot.configurationLimit` and
  `configuration.nix`'s `custom.nix.gc.keepGenerations` are both lowered
  from the shared default (10) to 5, ahead of any actual disk-pressure
  problem — same motivation as `defiant`'s cap, applied proactively here
  since 120GB is far smaller than `enterprise-d`/`excelsior`'s disks.
  Revisit both once real disk usage after Phase 2 is known.

## Known Gotchas

- **Only one declarative Lovelace dashboard is possible.** The nixpkgs
  `home-assistant` module's `lovelaceConfig`/`lovelaceConfigFile` generate
  content for a single dashboard file only — a second, independently-titled
  sidebar dashboard can't be declared from Nix. Unrelated concerns become
  separate views (tabs) inside the one dashboard instead — see
  [docs/smart-home.md § Declarative dashboards](../../docs/smart-home.md#declarative-dashboards-one-file-many-views).
- **`matter-server` looked "active (running)" while its websocket never
  opened.** Upstream fetches PAA root certs live from DCL on every
  `server.start()`; DCL currently serves a certificate that fails strict
  ASN.1 parsing in `cryptography`, raising an uncaught `ValueError` that the
  surrounding code doesn't catch (only `ClientError`/`TimeoutError` are).
  `start()` never finishes, port 5580 never binds, but the process doesn't
  crash or get restarted — first confirmed on `defiant` (100% reproducible
  on every restart via `journalctl`), and since `modules/matter.nix` is a
  plain shared module with no host-specific logic, the same failure applies
  here. Fixed by pinning static PAA certs into the package build instead of
  fetching them at runtime — see `modules/matter.nix` and
  [docs/smart-home.md § Matter](../../docs/smart-home.md#matter-pinned-paa-root-certs-not-live-dcl-fetch).
  Tracked upstream at
  [nixpkgs#377136](https://github.com/NixOS/nixpkgs/issues/377136).
- **Core HA's `linkplay` integration never sets up against the Wiim Pro
  units** — its `getMetaInfo` discovery call gets the literal string
  `"Failed"` back instead of JSON, so the config flow dies silently before
  anything reaches the UI. Replaced with the community `wiim` integration,
  packaged declaratively via `services.home-assistant.customComponents`
  instead of `extraComponents` — see
  [docs/smart-home.md § Wiim](../../docs/smart-home.md#wiim-community-integration-not-core-linkplay).
  Tracked upstream at
  [home-assistant/core#145132](https://github.com/home-assistant/core/issues/145132).
- **iOS companion app failed to connect with "The mobile_app component is not
  loaded."** `"mobile_app"` was already in `extraComponents`, which installs
  the package but doesn't cause HA to load it, and `mobile_app` has no "Add
  Integration" UI flow to trigger setup afterward — it's driven entirely by
  the companion app's own registration call, the very call that was failing.
  Fixed by adding `mobile_app = {}` to `services.home-assistant.config` in
  `modules/home-assistant.nix`, same fix shape as the existing `sun` entry —
  see
  [docs/smart-home.md § Home Assistant](../../docs/smart-home.md#home-assistant).
- **"The HTTP YAML configuration is deprecated" repair notice.** Newer HA
  versions stop reading `config.http.*` from YAML entirely (from `2027.2.0`)
  in favor of Settings > System > Network; this instance had already
  auto-imported the previous YAML values (`trusted_proxies`/
  `use_x_forwarded_for`, needed for Traefik's reverse proxy) into its own
  `.storage` before the warning appeared. Removed the now-redundant YAML
  block from `modules/home-assistant.nix` — safe here since the value
  already persists in storage independent of it, but a **fresh** HA install
  on any host needs a one-time manual step instead — see
  [docs/smart-home.md § HTTP config](../../docs/smart-home.md#http-config-no-longer-declarative).
- **iOS companion app setup silently times out when entering `<ip>:8123`,
  works with the FQDN (`home.coppertop.ca`).** `modules/home-assistant.nix`
  simply never opens port 8123 itself, and `configuration.nix`'s
  `firewall.extraCommands` only opens 8123 from `192.168.20.0/24` for Sonos
  UPnP callbacks — a client on any other VLAN can't reach 8123 directly.
  Traefik's 443 is open broadly via `custom.traefik`, so the FQDN (proxied to
  HA) connects fine; a raw IP:port entry just hangs with no error. Always use
  `home.coppertop.ca` for companion app / client setup, never `<ip>:8123`.
- **`services.home-assistant.openFirewall` is gone upstream — defining it at
  all (even `false`) is now an eval-time assertion failure.** nixpkgs used to
  determine the frontend port by parsing it out of HA's rendered YAML config
  at eval time; that's no longer possible (HTTP config moved out of YAML —
  see the entry above), so the option was removed via
  `mkRemovedOptionModule` regardless of the value assigned to it. Fixed by
  deleting the `openFirewall = false;` line from `modules/home-assistant.nix`
  — it was a no-op even before the removal (nothing opened 8123
  declaratively; that's what the manual `firewall.extraCommands` rule above
  is for), so removing it changes no runtime behavior. If HA's frontend port
  is ever reconfigured off 8123, the port has to be updated by hand in the
  two places that now hardcode it — `hosts/reliant/configuration.nix`'s
  `firewall.extraCommands` and `modules/home-assistant.nix`'s Traefik route
  registration — since nixpkgs can no longer discover it automatically. See
  [docs/smart-home.md § Firewall](../../docs/smart-home.md#firewall-openfirewall-removed-upstream).
- **BambuBuddy's printer telemetry never showed up in Home Assistant on its
  own.** Confirmed against BambuBuddy's own `mqtt_relay.py` source: it
  publishes plain JSON on plain MQTT topics with no Home Assistant Discovery
  messages, unlike Zigbee2MQTT's `zigbee2mqtt/bridge/...` topics — not a bug,
  just needed entities defined by hand. Fixed by
  `hosts/reliant/home-assistant/bambuddy-printers.nix` against
  `services.home-assistant.config.mqtt`. Two related caveats not yet
  resolved: `progress`/`remaining_time`'s numeric scale (percent vs. fraction,
  minutes vs. seconds) is unconfirmed — the only real payload captured had
  the printer `IDLE` with both at `0` — and the `mqtt:`-domain YAML shape used
  there wasn't checked against a live instance or fetchable upstream docs
  (outbound access to `home-assistant.io` was blocked in the sandbox that
  wrote it). See
  [docs/smart-home.md § BambuBuddy](../../docs/smart-home.md#bambuddy-manual-mqtt-entities-no-discovery).
- **No `camera:` platform here can be assigned to an area, so the camera is a
  template `image` instead.** `mjpeg` and `generic` are config-entry-only and
  silently produce nothing from YAML; `ffmpeg` works and gives live video,
  but its `PLATFORM_SCHEMA` has no `unique_id` and a legacy YAML platform has
  no other way to set one. Without a `unique_id` an entity never enters the
  entity registry, and area and device assignment both live there — HA says
  so outright: "this entity does not have a unique ID, therefore its settings
  cannot be managed from the UI". The `ffmpeg` version was deployed first and
  hit exactly that. `home-assistant/bambuddy-printers.nix` now declares a
  `template:` → `image:` entity, which does accept `unique_id`, at the cost
  of being a still that refreshes on a trigger rather than live video. Add
  the MJPEG IP Camera integration through the UI if a live feed is wanted —
  that route is a config entry, so it gets both, but it cannot come from Nix.
  Also confirmed live: the LAN-facing form of the URL
  (`reliant.local:8000/...`) hangs rather than erroring — port 8000 only
  binds loopback and isn't opened in the firewall (the firewall drops rather
  than rejects), so the entity must dial `127.0.0.1`;
  `bambuddy.coppertop.ca/camera/1` (through Traefik) is the browser-facing
  page, not this API path. Full reasoning in
  [docs/smart-home.md § Camera](../../docs/smart-home.md#camera-template-image-not-a-camera-platform).
  [docs/smart-home.md § Camera feed](../../docs/smart-home.md#camera-feed-platform-ffmpeg-never-mjpeg-or-generic).
- **Bambuddy refuses to add a printer it cannot currently reach**, so
  declarative printers cannot be a one-shot job. `POST /api/v1/printers/`
  runs `printer_manager.test_connection()` and raises 400
  `printer_connection_failed` unless the MQTT probe succeeds within 8s —
  upstream added that check on purpose, because rows created from a mistyped
  access code turned into support tickets. A printer that is powered off,
  off the LAN, or out of LAN Only + Developer Mode therefore cannot be
  provisioned at that moment, however correct the Nix is. That is why
  `bambuddy-provision` runs on a timer and reports exit 75 rather than
  failing for good — see § Declarative printers.
- **An enabled virtual printer binds ports whether or not the firewall lets
  anyone reach them.** The two are separate switches with nothing connecting
  them: Bambuddy starts the listeners as soon as an enabled row exists, and
  `virtualPrinter.openFirewall` is what makes them reachable. On this host
  the second is off (AdGuard holds 3000), so the virtual printer looks
  healthy in the UI while nftables silently drops every slicer connection —
  a refusal Bambuddy's own logs never see.
  `modules/bambuddy-provision.nix` emits an eval-time warning for that exact
  pairing. If the bind of port 3000 itself is refused because AdGuard already
  holds it, upstream logs `Bind server port 3000 already in use, skipping`
  and keeps serving 3002; it does not crash, and it does not disturb AdGuard.
- **`custom.homepage`'s port (8082) collided with Zigbee2MQTT's frontend,
  also 8082.** Confirmed live: `homepage-dashboard.service` failed
  (`EADDRINUSE`) on the first deploy with both enabled on this host. Moved to
  8083 in `modules/homepage.nix` — same class of conflict as
  `zwave-js`/AdGuard (3000, above) and `bambuddy`/AdGuard (3000, § Bambuddy).
- **Adding a static IP to `enp3s0` silently disabled DHCP and took this host
  off the network.** `networking.interfaces.<name>.useDHCP` defaults to
  `null`, which nixpkgs resolves as "DHCP only if `ipv4.addresses` is empty"
  — so adding the virtual printer's secondary bind IP without also setting
  `useDHCP = true` dropped the DHCP-assigned primary (`192.168.20.15`) the
  moment it activated, and with it the default route and nameservers, since
  DHCP is their only source (no `networking.defaultGateway` is set anywhere
  in this repo). Symptom: the host answers only from within `192.168.20.0/24`
  — the switch still shows the port up, and a power cycle does not help,
  because the broken generation is the one that boots. Recovery was to reach
  it from a client on its own subnet, at the static `.40`, and deploy with
  `useDHCP = true` restored. See
  [docs/homelab-network.md § Dedicated Bind IPs](../../docs/homelab-network.md#dedicated-bind-ips-for-lan-emulation-services).
- **With DHCP restored, that same static IP then broke every Matter device.**
  Two addresses in one `/24` means the first one added becomes the subnet's
  primary and supplies the default source address for on-subnet traffic —
  and `network-addresses-enp3s0.service` runs before dhcpcd gets its lease,
  so the static `.40` won. `ip route get 192.168.20.84` returned `src
  192.168.20.40`, and `matter-server` logged `Unable to establish CASE
  session with Node 1` for every commissioned node: Matter's session
  handshake is address-sensitive and the controller was talking to them from
  an address they had no session with. The default route was unaffected
  (dhcpcd pins `src` on it), so everything *routed* looked fine — which is
  why this hid. Every appliance holding controller state by address (Sonos
  UPnP callbacks, HomeKit, Apple TV) is exposed the same way. Fixed by
  removing the secondary address entirely; it returns only with the virtual
  printer, marked `preferred_lft 0` so it can never be chosen as a source.

## Backups

`custom.backups` is enabled, matching `enterprise-d`'s precedent (not
`excelsior`'s — that host lacking backups is an existing gap, not a pattern
to copy). The `thomasga` (home directory) job reuses `enterprise-d`'s
job-keyed `thomasga` restic-password and NAS-SMB-credentials secrets: both
are keyed to the backup job name, not the machine, and the restic repo path
already includes the hostname, so sharing these secrets across hosts doesn't
collide their backup data — see
[docs/secrets.md § Secret Inventory](../../docs/secrets.md#secret-inventory).

Phase 2 adds four more entries — `hass`, `zigbee2mqtt`, `zwave-js`,
`adguardhome` — mirroring `defiant`'s own backup jobs for the same services.
Same job-keyed sharing as `thomasga` above: each reuses `defiant`'s existing
`restic-password` secret rather than a new one, since the repo path already
disambiguates by hostname. All four confirmed running clean.
`zwave-js`'s backup path is `/var/cache/zwave-js`, not `/var/lib/zwave-js` —
confirmed live that the latter is never created (see the comment in
`hosts/reliant/configuration.nix`).

The `bambuddy` entry (`/var/lib/bambuddy`) is the one job here with **no
existing job-keyed secret to reuse** — it needs a new
`secrets/bambuddy/restic-password.age` and the matching `age.secrets` entry in
`hosts/reliant/secrets.nix` from `secrets-warden`. Until that lands the job
runs and skips itself ("Missing restic password file"), so it is a pending
hand-off rather than a broken unit.

## Secrets

`hosts/reliant/secrets.nix` declares, beyond the Phase 1 SSH/NAS entries, six
secrets — **all of them reused from `defiant`'s existing `.age` files**, none
newly created. Four are named for what they hold or which hardware they're
tied to, not for `defiant` (see
[docs/secrets.md § Shared hardware and domain secrets](../../docs/secrets.md#shared-hardware-and-domain-secrets)):

- `traefik/cloudflare-api-token` — just an API credential, not tied to either
  host's identity.
- `zigbee/network-key` — matched to the physical coordinator's own NVRAM,
  not the host; reusing it is what let already-paired Zigbee devices keep
  working without a re-pair once the coordinator moved (confirmed live).
- `location/coordinates` — home-address coordinates, not host- or
  radio-specific.
- `zwave/secrets` — matched to the physical controller's own NVM, same
  reasoning as the Zigbee key.
- `hass/restic-password`, `zigbee2mqtt/restic-password`,
  `zwave-js/restic-password`, `adguardhome/restic-password` — restic-password
  secrets are job-keyed, not machine-keyed (docs/secrets.md § Secret
  Inventory), and the restic repo path already includes the hostname, so
  sharing the password doesn't collide the two hosts' backup data — same
  pattern as `thomasga`'s job above.

Two Bambuddy secrets are **pending** and do not exist yet, both from
`secrets-warden`, both declared with no `owner` (read by root units):

- `bambuddy/restic-password` — for the backup job, see § Backups.
- `bambuddy/virtual-printer-access-code` — the access code a slicer presents
  to the `Bambuddy` virtual printer, referenced by
  `custom.bambuddy.virtualPrinters`. **Exactly 8 characters**; Bambuddy
  rejects any other length. It is the virtual printer's own code, unrelated
  to any real printer's. Until it exists, `bambuddy-provision.service`
  reports the virtual printer as pending on each tick and creates nothing.

`reliant` is now a rekeyed recipient of all five — confirmed live: the config
evaluates, all four appliance services (DNS/Traefik, Home Assistant,
Zigbee2MQTT, Z-Wave JS) and ADS-B are up and using them successfully.

## Provisioning

See [docs/provisioning.md](../../docs/provisioning.md) (the generic `disko`
flow, Steps 1–7) for the full enroll → install → first-boot process.
Host-specific notes:

- Step 1 (Phase 1 PR) is done: `hosts/reliant/` is defined and registered in
  `flake.nix` as `nixosConfigurations."reliant"`.
- Step 2 (enrollment) is done: `tools/enroll.py reliant` generated the age
  identity and SSH login key. `hosts/reliant/secrets.nix` was pre-created
  with an empty `age.secrets` block by the Phase 1 PR, so enroll.py's own
  auto-wiring was skipped (it only writes that file when it doesn't already
  exist) — the `thomasga/ssh-id-ed25519-reliant` entry was added by hand
  after the fact. This PR's own secrets were a separate hand-off, now done
  — see § Secrets above.
- The LUKS passphrase prompt in `install.py` is vestigial for this host —
  disko has no LUKS here, the value is unused.
- The machine has been physically installed and first-booted. The SSH host
  key is pinned in `lib/ssh-hosts.nix`, and the reserved LAN IP
  (`192.168.20.15`) is confirmed against its Unifi DHCP reservation.
- `home-manager.users.thomasga` is now attached in `hosts/reliant/default.nix`
  (`./home/thomasga.nix`, mirroring `excelsior`'s headless profile and naming
  `ssh-id-ed25519-reliant` as its SSH identity secret), and
  `flake.nix` has the matching `homeConfigurations."thomasga@reliant"` entry —
  this closes out the hand-off noted above.
