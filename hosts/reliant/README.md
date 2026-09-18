# reliant

This host is the homelab server. It replaced `defiant` (Raspberry Pi 4, retired) via a single combined migration PR that landed `custom.dns`/`custom.traefik` (owned by `homelab-network`, see [docs/homelab-network.md](../../docs/homelab-network.md)) and the appliance layer — Home Assistant, MQTT, Matter, Zigbee, Z-Wave, ADS-B (owned by `smart-home`, see [docs/smart-home.md](../../docs/smart-home.md)). `defiant` has since been fully retired and removed from the flake.

The LAN's DHCP-advertised DNS server is this host's own IP (`192.168.20.15`) in Unifi — `reliant` is the DNS primary.

**Still open**: AdGuard's filter/allow/deny-list configuration wasn't part of the Home Assistant restore and hasn't been migrated — `reliant`'s AdGuard is a fresh instance; Z-Wave device-level control (beyond the driver being healthy) not yet spot-checked.

## Services

`custom.dns` (unbound + AdGuard Home) and `custom.traefik` run on this host's own reserved LAN IP, `192.168.20.15` — now the LAN's actual DNS primary (see above). See [docs/homelab-network.md](../../docs/homelab-network.md) for the full design; host-specific facts:

- `dns1.coppertop.ca` → this host's own AdGuard Home admin UI.
- `dns2.coppertop.ca` → `excelsior`'s AdGuard Home admin UI, proxied cross-host by a manual router (see docs/homelab-network.md § Second DNS Instance (excelsior)).
- `custom.traefik.acme.environmentFile` points at `/run/agenix/traefik/cloudflare-api-token` — **reused** from `defiant`'s existing secret, not a new one (it's just an API credential, not tied to either host's identity). Cert issuance succeeded.

### lldap + Authelia (web SSO)

**Newly added, not yet deployed or confirmed on this hardware** — see [docs/homelab-network.md § Authelia Forward-Auth](../../docs/homelab-network.md#authelia-forward-auth-lldap--authelia-sso) for the full design.

- `ad.coppertop.ca` → lldap's own admin UI (`custom.lldap`). Never gated by Authelia — see that doc's § Self-Lockout Rule.
- `auth.coppertop.ca` → Authelia's own login portal (`custom.authelia`). Also never gated by Authelia, same reason.
- `dns1.coppertop.ca`/`dns2.coppertop.ca` (AdGuard admin UIs), `zigbee.coppertop.ca` (Zigbee2MQTT), `dcs.coppertop.ca` (excelsior's DCS webtop desktop), `dcs-control.coppertop.ca` (excelsior's DCS start/stop control page — **not** its `/hooks` webhook, which stays ungated since it's called machine-to-machine, not from a browser), and `bambuddy.coppertop.ca` are gated by the `authelia@file` forward-auth middleware (`custom.authelia.protectedSubdomains`). None of these have a login of their own. Several of these routers are self-registered inside modules this host's file doesn't own (`modules/zigbee.nix`, owned by `smart-home`; `modules/bambuddy.nix`) — `hosts/reliant/configuration.nix` layers the middleware onto them as a data overlay rather than editing those modules; see `docs/homelab-network.md` § Traefik Route Registration.
- **`home.coppertop.ca` (Home Assistant) is deliberately not on that list.** Forward-auth would just add a redundant second login in front of HA's own, not real SSO. Real SSO for HA is a distinct capability instead: Authelia runs as an OpenID Connect 1.0 provider (`custom.authelia.oidc`, coexisting with the LDAP-backed forward-auth above on the same instance), with HA registered as an OIDC client (`custom.authelia.oidc.homeAssistant`) via the third-party [`hass-oidc-auth`](https://github.com/christiaangoossens/hass-oidc-auth) HACS component — see [docs/homelab-network.md § OIDC Provider](../../docs/homelab-network.md#oidc-provider) for the full design. Installing `hass-oidc-auth` and HA's own `auth_oidc` config block is `smart-home`'s side, wired in `modules/home-assistant.nix`'s `custom.home-assistant.oidc` and this host's `configuration.nix` — see [docs/smart-home.md § OIDC Login](../../docs/smart-home.md#oidc-login-authelia-sso). **Not yet functional**: still missing the `home-assistant/oidc-client-secret` secret and the real package hash for the `hass-oidc-auth` HACS component, both listed in § Secrets and § Known Gotchas below.
- **`thomasga` (Geoffrey Thomas) has a real lldap account** — `custom.lldap.bootstrap.users` in `hosts/reliant/configuration.nix`, no `passwordFile` (set by hand through lldap's own UI, `ad.coppertop.ca`, on first login, not declaratively). To add another household member: append another entry the same way. Registering TOTP/WebAuthn 2FA with Authelia is also a self-service, one-time UI step (Authelia's own portal, `auth.coppertop.ca`, prompts for it on first login) — not something this repo can pre-provision.
- **TODO: password-reset email.** No SMTP notifier is configured — Authelia's password-reset/notification emails currently just write to a local file (`/var/lib/authelia-main/notification.txt`) instead of being sent anywhere. Needs a real SMTP relay's credentials before the password-reset flow is actually usable end-to-end.

### Ports

Every port this host binds, in ascending order — the complete list for `reliant`. It runs the densest service stack in the fleet, and every port collision this repo has hit has been on this host or its `defiant` predecessor — so check this table before assigning or moving any port here, and update it in the same commit ([docs/architecture.md § Placement Rule](../../docs/architecture.md#placement-rule)).

| Port | Protocol | Purpose | Exposure |
| --- | --- | --- | --- |
| 22 | tcp | SSH, `services.openssh` with `openFirewall = true` | LAN (firewall open); key-only auth, no password/root login |
| 53 | tcp+udp | AdGuard Home resolver, `custom.dns` | Bound `0.0.0.0`; UDP 53 opened to the LAN by `modules/dns.nix` (TCP 53 deliberately not opened) |
| 80, 443 | tcp | Traefik entry points (`web`/`websecure`), `custom.traefik` | LAN/WAN (firewall open) — every proxied service is reached through 443 here, never its own port |
| 322, 990, 2024–2026, 3000, 3002, 6000, 8883, 50000–50029 | tcp | Bambuddy virtual printer — bind/detect, RTSPS camera, FTPS, A1/P1S protocol, file tunnel, MQTT, FTP passive range (sized by `virtualPrinter.count`, 3 here). Hardcoded upstream in `bind_server.py`, started by the app whenever `custom.bambuddy` runs | Firewall closed (`virtualPrinter.openFirewall` off). Its 3000 is the same 3000 AdGuard holds below and neither side is configurable — `modules/bambuddy.nix` asserts on the pair; see § Bambuddy |
| 1883 | tcp | Mosquitto MQTT broker, `custom.mqtt` | 127.0.0.1 only |
| 3000 | tcp | AdGuard Home admin UI, `custom.dns` (upstream default) | Bound `0.0.0.0`, `openFirewall = false`; reached through Traefik at `dns1.coppertop.ca` |
| 3001 | tcp | zwave-js websocket, `custom.zwave.port` — overridden here because the module default (3000) is AdGuard's admin UI | Firewall closed; Home Assistant connects over localhost |
| 3890 | tcp | lldap's own LDAP protocol port, `custom.lldap.ldapPort` (upstream default) | 127.0.0.1 only — Authelia is the only consumer, same host |
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
| 9091 | tcp | Authelia, `custom.authelia.port` (upstream default) | 127.0.0.1 only; Traefik at `auth.coppertop.ca`, and the `authelia@file` forward-auth middleware's own callback target |
| 17170 | tcp | lldap web UI/GraphQL API, `custom.lldap.httpPort` (upstream default) | 127.0.0.1 only; Traefik at `ad.coppertop.ca` |
| 30001–30005, 30104 | tcp | dump1090's raw/Beast/SBS feed listeners, `custom.adsb` (it runs dump1090 with `--net`, so these are dump1090's own defaults) | Bound `0.0.0.0`, firewall closed |

`custom.backups` and `custom.ddns` bind nothing — both are outbound-only (SMB to the NAS, HTTPS to Cloudflare).

Provisioning steps are the generic `disko` flow in [docs/provisioning.md § Provision Types](../../docs/provisioning.md#provision-types) onward (same as `enterprise-d`/`excelsior`).

## Device Pairing Notes

- **ecobee thermostats (2×, HomeKit)** — `home-assistant/ecobee-climate.nix` covers the two zones actually installed today, `climate.main_and_basement` and `climate.upstairs`; a garage thermostat and upstairs AC are planned but not installed, and will land as their own PRs once that hardware exists rather than as unused code now. Unpair from Apple Home first — a HomeKit accessory accepts only one controller. The setup code is on the thermostat: Menu → Settings → HomeKit. After pairing, rename each climate entity to match the file's entity list (or edit that list to match). Set each thermostat's hold action to **Until I change it** so its own schedule never overrides the automations' setpoint — Home Assistant/HomeKit has no way to set this remotely, so it stays a manual per-thermostat step. Switch seasons by toggling `input_boolean.climate_summer_mode` in the HA UI — it applies immediately, no rebuild needed.
- **Presence (person entities)** — the ecobee automations key off `zone.home`, which needs at least one `person` entity with a device tracker attached. Install the HA companion app on each phone, then HA → Settings → People, attach each phone's device tracker.
- **Apple TV (3×)** — in HA → Integrations, add each Apple TV and complete the on-screen/HA PIN pairing. Name each device during pairing as `Apple TV Upstairs Living Room`, `Apple TV Basement Living Room`, and `Apple TV Geoff's Office` (matching their physical locations) so HA derives predictable, clearly scoped entity_ids: `media_player.apple_tv_upstairs_living_room`, `media_player.apple_tv_basement_living_room`, and `media_player.apple_tv_geoff_s_office`.
- **Broadlink RM4 mini (Geoff's Office AV IR blaster)** — in HA → Integrations, add it (config-flow, discovers the RM4 automatically on the LAN); it lands as `remote.geoff_s_office_wi_fi_universal_remote`. `home-assistant/appletv-av.nix` bakes all four commands in as raw `b64:` codes rather than referencing device/command names, so nothing depends on this pairing's live `.storage` state. That only matters again if the projector or receiver is physically replaced, since the codes are specific to each unit's own remote/protocol:
  - **Projector replaced**: learn its two commands, one press per command aimed at its own remote while the RM4's learn light is on: Developer Tools → Actions → `remote.learn_command`, for `device: projector, command: PowerOn` and `PowerOff`. Pull the two codes out of storage (`ssh <host> sudo cat /var/lib/hass/.storage/broadlink_remote_<mac>_codes`) and paste them into `epsonPowerliteHomeCinema3020PowerOnCode`/`epsonPowerliteHomeCinema3020PowerOffCode` in the Nix file.
  - **Receiver replaced**: its remote almost certainly won't share this unit's NEC address/command bytes even if it's another Yamaha — see `docs/smart-home.md` § Receiver power for how `yamahaHtr4063PowerOnCode`/`yamahaHtr4063PowerOffCode` were derived; the reverse-engineering has to be redone for the new unit. This integration only drives receiver/projector *power* — Apple TV volume for the same AV chain goes through CEC instead (Apple TV Settings → Remotes and Devices → Volume Control → Auto).

## Bambuddy (3D Printing)

`custom.bambuddy` runs Bambuddy natively (`pkgs/bambuddy.nix` — the upstream image is not used; see the header comment there for why) plus the OrcaSlicer slicing sidecar as a podman container. Newly added and not yet run against real hardware here. Host-specific notes:

- Reached at `bambuddy.coppertop.ca` through this host's Traefik. The app itself binds `127.0.0.1:8000` only, the same posture as every other service here.
- **Each printer needs LAN Only Mode + Developer Mode enabled**, on the printer: Settings → Network → LAN Only Mode, then Developer Mode (it only appears after LAN Only Mode is on). Note the Access Code, IP, and serial — those three are what the first-run wizard asks for. Without Developer Mode the printer is read-only monitoring at best. Also enable **"Store sent files on external storage"** in the slicer, or Bambuddy has no 3MF to archive.
- The slicing sidecar listens on `127.0.0.1:3003` and is called only by Bambuddy on this same host — no Traefik route, no firewall opening. Its image is **linux/amd64 only** upstream (no ARM64 build, no source for the patched OrcaSlicer CLI inside it), which is fine here and would not be on an ARM host. `SLICER_API_URL` is set from the module, so nothing needs entering in Settings → Slicer.
- **The virtual-printer feature is off at the firewall on this host and cannot simply be turned on.** It binds ports 3000/3002 unconditionally — hardcoded in upstream's `bind_server.py`, because a slicer looks for a real printer on exactly those ports — and 3000 is already AdGuard Home's admin UI here. `modules/bambuddy.nix` asserts on that combination rather than letting it fail at bind time; moving `services.adguardhome.port` is the prerequisite.
- Data (SQLite database, 3MF/print archive) lives in `/var/lib/bambuddy`, owned by a fixed `bambuddy` system user. Logs are in `/var/log/bambuddy`.

## Machine Files

| File | Purpose |
| --- | --- |
| `configuration.nix` | Boot, hardware, networking, `custom.users`, `custom.backups`, (Phase 2) `custom.dns`/`custom.traefik`/`custom.home-assistant`/`mqtt`/`matter`/`zigbee`/`zwave`/`adsb` all migrated from `defiant`, plus `custom.bambuddy` (new here) |
| `hardware.nix` | systemd-boot, EFI, Intel microcode, generic firmware (template, not a hardware scan — see Hardware And Access below) |
| `power.nix` | Explicit no-hibernate/no-suspend statement for this always-on headless host |
| `disko.nix` | GPT layout: ESP, swap, plain ext4 root (no btrfs/snapper — see the comment in the file for why) |
| `default.nix` | Imports `configuration.nix` and attaches `thomasga`'s home-manager config (`./home/thomasga.nix`) |
| `secrets.nix` | `age.secrets` declarations for this host, including the Phase 2 smart-home entries — see § Secrets below |
| `home-assistant/` | Declarative HA automations, one file per concern — mostly a copy of `hosts/defiant/home-assistant/`, plus `ecobee-climate.nix` (new here, not migrated) |
| `provision-type` | `disko` |

## Hardware And Access

- Gigabyte GB-BXi5-4200 "Brix" mini PC — Intel Core i5-4200U (Haswell), 8GB DDR3L RAM (single Kingston SODIMM installed, second slot empty), Crucial M500 120GB mSATA SSD. USB3, gigabit LAN, HDMI.
- No TPM2 confirmed on this hardware — `disko.nix` uses no LUKS/TPM, unlike `enterprise-d`. Do not adopt that host's LUKS+TPM pattern here without confirming a TPM2 chip is actually present.
- The disk is expected to enumerate as `/dev/sda` (SATA/mSATA, not NVMe) — `disko.nix`'s default matches that, but **verify with `lsblk` at install time** (Step 5) before confirming the target device; disko destroys whatever it's pointed at.
- `hardware.nix` is a best-effort template mirroring `excelsior`'s shape (systemd-boot, EFI, redistributable firmware, Intel microcode) — it is **not** a `nixos-generate-config` scan, since this machine has not been physically installed yet. Verify against the installer's own hardware detection during Step 5 and correct here if the Brix needs anything this omits.
- Reserved LAN IP `192.168.20.15`, set as a DHCP reservation in Unifi — distinct from `defiant`'s own reservation (`192.168.20.10`, which stays with `defiant` — cutover repointed Unifi's DHCP-advertised DNS server at this IP directly rather than reassigning `defiant`'s reservation). Consumed by `custom.dns.lanIp` — see § Services above.
- Headless. `profiles/desktop` is deliberately **not** imported — there is no display server. `profiles/dev` is also not imported — the appliance service set migrated in this PR (Home Assistant, Zigbee2MQTT, Z-Wave JS, etc.) doesn't need it.
- Zigbee coordinator (`/dev/ttyUSB0`, vendor ID `0658`) and Z-Wave controller (`/dev/ttyACM0`, vendor ID `10c4`) are passed through by the same `udev.extraRules` entry `defiant` uses, into the `dialout` group; `thomasga` is in that group here too. Both dongles are physically moved here and paired devices respond without a re-pair.
- SSH key only: `PasswordAuthentication`, `KbdInteractiveAuthentication`, and `PermitRootLogin` are all off.
- `security.sudo.wheelNeedsPassword = false`, same reasoning as `defiant` and `excelsior`: the authorized-key check is the real access gate, and a sudo password on top of it only blocks unattended `nixos-rebuild --target-host` deploys.
- The bare `reliant` hostname isn't resolvable — use the mDNS `.local` name for deploys regardless of DNS cutover status:

  ```bash
  nixos-rebuild switch --flake .#reliant --target-host thomasga@reliant.local --sudo
  ```

## Disk Layout And GC Tuning

- `disko.nix`: GPT with a 1G ESP, 4G swap, and the rest as a plain ext4 root (no LVM) — not `excelsior`'s btrfs-with-subvolumes pattern, which exists there to keep a large, fast-growing DCS install out of snapper's timeline snapshots on a 1TB disk with headroom to spare. This disk is 120GB total, smaller than that DCS install alone, and Phase 2 is expected to migrate `defiant`'s growing homelab state onto it. Adding btrfs CoW + snapper on top risks the disk-pressure problem `defiant`'s fixed-size SD card hit (see git history — that host and its README are now retired). Plain ext4 avoids that; btrfs + snapper can be added later if there turns out to be headroom to spare.
- `hardware.nix`'s `boot.loader.systemd-boot.configurationLimit` and `configuration.nix`'s `custom.nix.gc.keepGenerations` are both lowered from the shared default (10) to 5, proactively, ahead of any actual disk-pressure problem — same motivation as `defiant`'s cap, since 120GB is far smaller than `enterprise-d`/`excelsior`'s disks. Revisit both once real disk usage after Phase 2 is known.

## Known Gotchas

- **Only one declarative Lovelace dashboard is possible.** The nixpkgs `home-assistant` module's `lovelaceConfig`/`lovelaceConfigFile` generate content for a single dashboard file only — a second, independently-titled sidebar dashboard can't be declared from Nix. Unrelated concerns become separate views (tabs) inside the one dashboard instead — see [docs/smart-home.md § Declarative dashboards](../../docs/smart-home.md#declarative-dashboards-one-file-many-views).
- **`matter-server` looked "active (running)" while its websocket never opened.** Upstream fetches PAA root certs live from DCL on every `server.start()`. DCL currently serves a certificate that fails strict ASN.1 parsing in `cryptography`, raising an uncaught `ValueError` the surrounding code doesn't catch (only `ClientError`/`TimeoutError` are). `start()` never finishes and port 5580 never binds, but the process doesn't crash — first confirmed on `defiant` (100% reproducible via `journalctl`), and `modules/matter.nix` has no host-specific logic so the same failure applies here. Fixed by pinning static PAA certs into the package build instead of fetching at runtime — see `modules/matter.nix` and [docs/smart-home.md § Matter](../../docs/smart-home.md#matter-pinned-paa-root-certs-not-live-dcl-fetch). Tracked upstream at [nixpkgs#377136](https://github.com/NixOS/nixpkgs/issues/377136).
- **Core HA's `linkplay` integration never sets up against the Wiim Pro units** — its `getMetaInfo` discovery call gets the literal string `"Failed"` back instead of JSON, so the config flow dies silently before anything reaches the UI. Replaced with the community `wiim` integration, packaged declaratively via `services.home-assistant.customComponents` instead of `extraComponents` — see [docs/smart-home.md § Wiim](../../docs/smart-home.md#wiim-community-integration-not-core-linkplay). Tracked upstream at [home-assistant/core#145132](https://github.com/home-assistant/core/issues/145132).
- **iOS companion app failed to connect with "The mobile_app component is not loaded."** `"mobile_app"` was already in `extraComponents`, which installs the package but doesn't cause HA to load it, and `mobile_app` has no "Add Integration" UI flow to trigger setup afterward — it's driven entirely by the companion app's own registration call, the very call that was failing. Fixed by adding `mobile_app = {}` to `services.home-assistant.config` in `modules/home-assistant.nix`, same fix shape as the existing `sun` entry — see [docs/smart-home.md § Home Assistant](../../docs/smart-home.md#home-assistant).
- **"The HTTP YAML configuration is deprecated" repair notice.** Newer HA versions stop reading `config.http.*` from YAML entirely (from `2027.2.0`) in favor of Settings > System > Network. This instance had already auto-imported the previous YAML values (`trusted_proxies`/`use_x_forwarded_for`, needed for Traefik's reverse proxy) into its own `.storage` before the warning appeared. Removed the now-redundant YAML block from `modules/home-assistant.nix` — safe here since the value persists in storage independent of it, but a **fresh** HA install on any host needs a one-time manual step instead — see [docs/smart-home.md § HTTP config](../../docs/smart-home.md#http-config-no-longer-declarative).
- **iOS companion app setup silently times out when entering `<ip>:8123`, works with the FQDN (`home.coppertop.ca`).** `modules/home-assistant.nix` simply never opens port 8123 itself, and `configuration.nix`'s `firewall.extraCommands` only opens 8123 from `192.168.20.0/24` for Sonos UPnP callbacks — a client on any other VLAN can't reach 8123 directly. Traefik's 443 is open broadly via `custom.traefik`, so the FQDN (proxied to HA) connects fine; a raw IP:port entry just hangs with no error. Always use `home.coppertop.ca` for companion app / client setup, never `<ip>:8123`.
- **`services.home-assistant.openFirewall` is gone upstream — defining it at all (even `false`) is now an eval-time assertion failure.** nixpkgs used to determine the frontend port by parsing it out of HA's rendered YAML config; that's no longer possible now that HTTP config moved out of YAML (see the entry above), so the option was removed via `mkRemovedOptionModule` regardless of value. Fixed by deleting the `openFirewall = false;` line from `modules/home-assistant.nix` — it was already a no-op (nothing opened 8123 declaratively; that's what the manual `firewall.extraCommands` rule above is for), so this changes no runtime behavior. If HA's frontend port is ever reconfigured off 8123, it has to be updated by hand in the two places that now hardcode it — `hosts/reliant/configuration.nix`'s `firewall.extraCommands` and `modules/home-assistant.nix`'s Traefik route registration. See [docs/smart-home.md § Firewall](../../docs/smart-home.md#firewall-openfirewall-removed-upstream).
- **Home Assistant's OIDC SSO (`custom.home-assistant.oidc`) is wired but not deployable yet — two real gaps.** (1) `pkgs/home-assistant-oidc-auth.nix`'s `fetchFromGitHub.hash` is a `lib.fakeHash` placeholder — no local Nix toolchain was available to compute the real NAR hash when this was added. A build attempt will fail loudly on the mismatch; copy the real hash from that error before deploying (same recovery step as `docs/smart-home.md` § Matter's PAA cert re-pin). (2) `configuration.nix` already points `custom.home-assistant.oidc.clientSecretFile` at `/run/agenix/home-assistant/oidc-client-secret`, which doesn't exist yet — `home-assistant.service` will fail to start the moment this is deployed until `secrets-warden` creates it (see § Secrets above). Do not `nixos-rebuild switch` this change until both are resolved.
- **`custom.homepage`'s port (8082) collided with Zigbee2MQTT's frontend, also 8082.** `homepage-dashboard.service` failed (`EADDRINUSE`) on the first deploy with both enabled. Moved to 8083 in `modules/homepage.nix` — same class of conflict as `zwave-js`/AdGuard (3000, above) and `bambuddy`/AdGuard (3000, § Bambuddy).

## Backups

`custom.backups` is enabled, matching `enterprise-d`'s precedent (not `excelsior`'s — that host lacking backups is an existing gap, not a pattern to copy). The `thomasga` (home directory) job reuses `enterprise-d`'s job-keyed `thomasga` restic-password and NAS-SMB-credentials secrets: both are keyed to the job name, not the machine, and the restic repo path already includes the hostname, so sharing them across hosts doesn't collide backup data — see [docs/secrets.md § Secret Inventory](../../docs/secrets.md#secret-inventory).

Phase 2 adds four more entries — `hass`, `zigbee2mqtt`, `zwave-js`, `adguardhome` — mirroring `defiant`'s own backup jobs for the same services, each reusing `defiant`'s existing `restic-password` secret the same job-keyed way. All four run clean. `zwave-js`'s backup path is `/var/cache/zwave-js`, not `/var/lib/zwave-js` — the latter is never created (see the comment in `hosts/reliant/configuration.nix`).

The `bambuddy` entry (`/var/lib/bambuddy`) is the one job here with **no existing job-keyed secret to reuse** — it needs a new `secrets/bambuddy/restic-password.age` and the matching `age.secrets` entry in `hosts/reliant/secrets.nix` from `secrets-warden`. Until that lands the job runs and skips itself ("Missing restic password file"), a pending hand-off rather than a broken unit.

`lldap` (`/var/lib/lldap`) and `authelia` (`/var/lib/authelia-main`) are the same situation — brand-new services, each needing its own new `secrets/{lldap,authelia}/restic-password.age` plus the matching `age.secrets` entries from `secrets-warden`. Both skip themselves the same way until then. Authelia's database holds TOTP/WebAuthn registrations that aren't reconstructible from anywhere else, so this gap matters more than most.

## Secrets

`hosts/reliant/secrets.nix` declares, beyond the Phase 1 SSH/NAS entries, six secrets — **all of them reused from `defiant`'s existing `.age` files**, none newly created. Four are named for what they hold or which hardware they're tied to, not for `defiant` (see [docs/secrets.md § Shared hardware and domain secrets](../../docs/secrets.md#shared-hardware-and-domain-secrets)):

- `traefik/cloudflare-api-token` — just an API credential, not tied to either host's identity.
- `zigbee/network-key` — matched to the physical coordinator's own NVRAM, not the host; reusing it is what let already-paired Zigbee devices keep working without a re-pair once the coordinator moved.
- `location/coordinates` — home-address coordinates, not host- or radio-specific.
- `zwave/secrets` — matched to the physical controller's own NVM, same reasoning as the Zigbee key.
- `hass/restic-password`, `zigbee2mqtt/restic-password`, `zwave-js/restic-password`, `adguardhome/restic-password` — restic-password secrets are job-keyed, not machine-keyed (docs/secrets.md § Secret Inventory), and the restic repo path already includes the hostname, so sharing the password doesn't collide the two hosts' backup data — same pattern as `thomasga`'s job above.

`reliant` is now a rekeyed recipient of all five: the config evaluates, and all four appliance services (DNS/Traefik, Home Assistant, Zigbee2MQTT, Z-Wave JS) plus ADS-B are up and using them successfully.

**lldap + Authelia adds six more, none reused — all brand new, from `secrets-warden`:**

| Secret | Owner (agenix) | Consumer |
| --- | --- | --- |
| `lldap/admin-password` | `lldap` | `custom.lldap.adminPasswordFile` — lldap's own superuser password |
| `lldap/jwt-secret` | `lldap` | `custom.lldap.jwtSecretFile` — lldap's session JWT signing key |
| `authelia/jwt-secret` | none (default root) — `secrets.jwtSecretFile` is `LoadCredential`-backed, and systemd performs that copy as root before `authelia-main` is assumed | `custom.authelia.jwtSecretFile` — Authelia's password-reset JWT signing key |
| `authelia/storage-encryption-key` | none (default root) — same `LoadCredential` reasoning as `authelia/jwt-secret` above | `custom.authelia.storageEncryptionKeyFile` — encrypts TOTP/WebAuthn secrets in Authelia's own database |
| `authelia/ldap-bind-password` | `authelia-main` | Both `custom.authelia.ldap.bindPasswordFile` **and** `custom.lldap.bootstrap.users`' `authelia` entry's `passwordFile` — the same credential, read by two different services, so lldap and Authelia agree on it. `authelia-main` (not root) because Authelia reads this one via a raw environment variable, not `LoadCredential` — see docs/homelab-network.md § Known Gotchas. |
| `lldap/restic-password`, `authelia/restic-password` | n/a (restic runs as root) | The two new `custom.backups.users` entries above |

Note the `authelia/ldap-bind-password` secret is consumed by **two** hosts' worth of config on this one host — both `custom.lldap` (as one bootstrapped user's password) and `custom.authelia` (as its own bind credential) — so it needs to be readable by whichever system user actually reads each path: `lldap-bootstrap.service` runs as root (so any owner works for the copy `custom.lldap.bootstrap.users` references), but `custom.authelia.ldap.bindPasswordFile` specifically needs `authelia-main` read access.

**Authelia's OIDC provider (Home Assistant SSO) adds three more, all brand new, from `secrets-warden`:**

| Secret | Owner (agenix) | Consumer |
| --- | --- | --- |
| `authelia/oidc-issuer-private-key` | none (default root) | `custom.authelia.oidc.issuerPrivateKeyFile` — Authelia's OIDC issuer signing key (RSA, PKCS#8/PKCS#1, ≥2048 bits). Generate with `openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048`. Read via nixpkgs' own `secrets.oidcIssuerPrivateKeyFile` — unlike the LDAP bind password, this one **does** go through systemd `LoadCredential`, and systemd performs that copy as root during unit setup, so root-only `0400` is sufficient and is the narrower choice. |
| `authelia/oidc-hmac-secret` | none (default root) | `custom.authelia.oidc.hmacSecretFile` — signs OIDC JWTs. Generate with `openssl rand -base64 64 \| tr -d '\n=+/' \| head -c 64`. Also `LoadCredential`-backed (`secrets.oidcHmacSecretFile`), same root-only reasoning. |
| `authelia/oidc-client-secret-home-assistant-hash` | `authelia-main` | `custom.authelia.oidc.homeAssistant.clientSecretHashFile` — **not** a raw secret: Authelia only ever stores a pbkdf2-sha512 hash of Home Assistant's OIDC client secret. Generate both the raw secret and its hash together with `nix run nixpkgs#authelia -- crypto hash generate pbkdf2 --variant sha512 --random`; only the digest goes in this file. The raw secret goes into Home Assistant's own `auth_oidc.client_secret` — that's `smart-home`'s side, not managed by this file or this secret. Read directly at runtime via Authelia's own Go-template `secret` function, the same env-var-style direct read as `authelia/ldap-bind-password` (not `LoadCredential`) — see docs/homelab-network.md § OIDC Provider. |

**Home Assistant's own OIDC config (`smart-home`'s side of the same SSO feature) needs one more, not yet created — this is the outstanding blocker for turning the feature on:**

| Secret | Owner (agenix) | Consumer |
| --- | --- | --- |
| `home-assistant/oidc-client-secret` | none (default root) — same reasoning as `location/coordinates` above: this is an `EnvironmentFile`, read by systemd itself as root before `home-assistant.service` drops to its own user, not read by the `hass` user directly | `custom.home-assistant.oidc.clientSecretFile` (`modules/home-assistant.nix`) — the **raw** (pre-hash) half of the exact same shared secret `authelia/oidc-client-secret-home-assistant-hash` above stores the digest of. Generate both together with the one command in that row; the raw output (not the digest) goes here. **File contents must be `HASS_OIDC_CLIENT_SECRET=<raw value>`** (an `EnvironmentFile` line, not the bare value) — same KEY=VALUE shape as `location/coordinates`. `hosts/reliant/configuration.nix` already references `/run/agenix/home-assistant/oidc-client-secret`; until this secret exists and reliant is a recipient, `home-assistant.service` fails to start outright (`EnvironmentFile=` with a missing target is a hard systemd failure, not a soft warning) — do not deploy `custom.home-assistant.oidc.enable = true` before this exists. |

## Provisioning

See [docs/provisioning.md](../../docs/provisioning.md) (the generic `disko` flow, Steps 1–7) for the full enroll → install → first-boot process. Already done for this host: definition, enrollment, install, first boot, SSH host key pinning, and the `thomasga` home-manager attachment.
