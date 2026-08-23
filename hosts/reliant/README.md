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
healthy) not yet spot-checked.

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

Provisioning steps are the generic `disko` flow in
[docs/provisioning.md § Provision Types](../../docs/provisioning.md#provision-types)
onward (same as `enterprise-d`/`excelsior`).

## Device Pairing Notes

- **ecobee thermostats (3×, HomeKit)** — `home-assistant/ecobee-climate.nix`
  covers `climate.garage` (flat 14°C frost protection, no schedule), plus the
  two zones actually installed today, `climate.main_and_basement` and
  `climate.upstairs`; upstairs AC is planned but not installed, and will
  land as its own PR once that hardware exists rather than as unused code
  now. Unpair from Apple Home first — a HomeKit accessory accepts only one
  controller. The setup code is on the thermostat: Menu → Settings →
  HomeKit. After pairing, rename each climate entity to match the file's
  entity list (or edit that list to match). Set each thermostat's hold
  action to **Until I change it** (except the garage — see below) so the
  ecobee's own built-in schedule never overrides the automations' setpoint
  — Home Assistant/HomeKit has no way to set this remotely, so it stays a
  manual per-thermostat step. Switch seasons by toggling
  `input_boolean.climate_summer_mode` in the HA UI — it applies
  immediately, no rebuild needed. The garage automation also expects
  `binary_sensor.garage_motion` (its ecobee SmartSensor's motion entity,
  same pairing as the thermostat itself — rename to match if pairing
  assigns something different, same as the climate entity): it suppresses
  the hourly/startup reassert while there's been recent motion, and
  triggers a prompt reassert once motion's been clear for 30 minutes, so a
  manual bump made while actually working out there survives the whole
  visit instead of getting stomped on the next hourly tick.
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

## Machine Files

| File | Purpose |
| --- | --- |
| `configuration.nix` | Boot, hardware, networking, `custom.users`, `custom.backups`, and (Phase 2) `custom.dns`/`custom.traefik`/`custom.home-assistant`/`mqtt`/`matter`/`zigbee`/`zwave`/`adsb`, all migrated from `defiant` |
| `hardware.nix` | systemd-boot, EFI, Intel microcode, generic firmware (template, not a hardware scan — see Hardware And Access below) |
| `power.nix` | Explicit no-hibernate/no-suspend statement for this always-on headless host |
| `disko.nix` | GPT layout: ESP, swap, plain ext4 root (no btrfs/snapper — see the comment in the file for why) |
| `default.nix` | Imports `configuration.nix` only — no home-manager user attached yet |
| `secrets.nix` | `age.secrets` declarations for this host, including the Phase 2 smart-home entries — see § Secrets below |
| `home-assistant/` | Declarative HA automations, one file per concern — mostly a copy of `hosts/defiant/home-assistant/`, plus `ecobee-climate.nix` (new here, not migrated) |
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
- No `homeConfigurations."thomasga@reliant"` entry exists in `flake.nix` yet
  — it would import `hosts/reliant/home/thomasga.nix`, which doesn't exist.
  `user-provisioner` adds both together when attaching a user (Phase 2).
