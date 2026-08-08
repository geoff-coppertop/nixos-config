# reliant

**Phase 1 (machine provisioning) is confirmed up but not yet merged to
`master`** — this branch was created from the still-open Phase 1 branch, per
[docs/provisioning.md § Two Phases](../../docs/provisioning.md#two-phases).

This host is replacing `defiant` as the homelab server. Both halves of the
migration — `custom.dns`/`custom.traefik` (owned by `homelab-network`, see
[docs/homelab-network.md](../../docs/homelab-network.md)) and the appliance
layer: Home Assistant, MQTT, Matter, Zigbee, Z-Wave, ADS-B (owned by
`smart-home`, see [docs/smart-home.md](../../docs/smart-home.md)) — landed as
one combined PR, since both target this same new host as a single coordinated
migration rather than two independent changes. **Nothing here is live yet**:
the Zigbee and Z-Wave USB radios are still physically plugged into `defiant`,
several secrets this config depends on aren't created yet (see § Secrets
below), and this host isn't the DNS/DHCP primary. `defiant` keeps running
every one of these services untouched until the radios physically move and a
later cutover step reassigns the `192.168.20.10` DHCP reservation and removes
the homelab stack from `hosts/defiant/`.

## Services

`custom.dns` (unbound + AdGuard Home) and `custom.traefik` run on this host's
own reserved LAN IP, `192.168.20.15` — a fully separate, parallel stack from
`defiant`'s, not yet the DNS/DHCP primary (that's the cutover step above).
See [docs/homelab-network.md](../../docs/homelab-network.md) for the full
design; host-specific facts:

- `dns1.coppertop.ca` → this host's own AdGuard Home admin UI.
- `dns2.coppertop.ca` → `excelsior`'s AdGuard Home admin UI, proxied
  cross-host (the same manual router `defiant` also still carries — see
  docs/homelab-network.md § Second DNS Instance (excelsior)).
- `custom.traefik.acme.environmentFile` points at
  `/run/agenix/traefik/cloudflare-api-token` — **reused** from `defiant`'s
  existing secret (it's just an API credential, not tied to either host's
  identity), not a new one. See § Secrets below for what's still pending.

Provisioning steps are the generic `disko` flow in
[docs/provisioning.md § Provision Types](../../docs/provisioning.md#provision-types)
onward (same as `enterprise-d`/`excelsior`).

## Machine Files

| File | Purpose |
| --- | --- |
| `configuration.nix` | Boot, hardware, networking, `custom.users`, `custom.backups`, and (Phase 2) `custom.dns`/`custom.traefik`/`custom.home-assistant`/`mqtt`/`matter`/`zigbee`/`zwave`/`adsb`, all migrated from `defiant` |
| `hardware.nix` | systemd-boot, EFI, Intel microcode, generic firmware (template, not a hardware scan — see Hardware And Access below) |
| `power.nix` | Explicit no-hibernate/no-suspend statement for this always-on headless host |
| `disko.nix` | GPT layout: ESP, swap, plain ext4 root (no btrfs/snapper — see the comment in the file for why) |
| `default.nix` | Imports `configuration.nix` only — no home-manager user attached yet |
| `secrets.nix` | `age.secrets` declarations for this host, including the Phase 2 smart-home entries — see § Secrets below |
| `home-assistant/` | Declarative HA automations, one file per concern — a copy of `hosts/defiant/home-assistant/` |
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
  with `defiant` until the eventual cutover step). Consumed by
  `custom.dns.lanIp` — see § Services above.
- Headless. `profiles/desktop` is deliberately **not** imported — there is no
  display server. `profiles/dev` is also not imported — the appliance
  service set migrated in this PR (Home Assistant, Zigbee2MQTT, Z-Wave JS,
  etc.) doesn't need it.
- Zigbee coordinator (`/dev/ttyUSB0`, vendor ID `0658`) and Z-Wave controller
  (`/dev/ttyACM0`, vendor ID `10c4`) are passed through by the same
  `udev.extraRules` entry `defiant` uses, into the `dialout` group;
  `thomasga` is in that group here too. **Not yet physically true** — both
  dongles are still plugged into `defiant`; this rule is only ready for when
  they're moved.
- SSH key only: `PasswordAuthentication`, `KbdInteractiveAuthentication`, and
  `PermitRootLogin` are all off.
- `security.sudo.wheelNeedsPassword = false`, same reasoning as `defiant` and
  `excelsior`: the authorized-key check is the real access gate, and a sudo
  password on top of it only blocks unattended `nixos-rebuild --target-host`
  deploys.
- `reliant` alone isn't resolvable via the LAN's primary DNS until the
  cutover step reassigns the `192.168.20.10` reservation to it — `reliant`
  now runs its own resolver (§ Services above), but clients aren't pointed at
  it yet. Use the mDNS `.local` name until then:

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
  btrfs CoW + snapper snapshots on top of that here risks exactly the kind
  of disk-pressure problem documented in
  [hosts/defiant/README.md § Known Gotchas](../defiant/README.md#known-gotchas)
  for its SD card. Plain ext4 avoids that; btrfs + snapper can be added
  later if there turns out to be headroom to spare.
- `hardware.nix`'s `boot.loader.systemd-boot.configurationLimit` and
  `configuration.nix`'s `custom.nix.gc.keepGenerations` are both lowered
  from the shared default (10) to 5, ahead of any actual disk-pressure
  problem — same motivation as `defiant`'s cap, applied proactively here
  since 120GB is far smaller than `enterprise-d`/`excelsior`'s disks.
  Revisit both once real disk usage after Phase 2 is known.

## Backups

`custom.backups` is enabled, matching `enterprise-d`'s precedent (not
`excelsior`'s — that host lacking backups is an existing gap, not a pattern
to copy). The `thomasga` (home directory) job reuses `enterprise-d`'s
job-keyed `thomasga` restic-password and NAS-SMB-credentials secrets: both
are keyed to the backup job name, not the machine, and the restic repo path
already includes the hostname, so sharing these secrets across hosts doesn't
collide their backup data — see
[docs/secrets.md § Secret Inventory](../../docs/secrets.md#secret-inventory).

Phase 2 adds three more entries — `hass`, `zigbee2mqtt`, `zwave-js` — mirroring
`defiant`'s own backup jobs for the same services. Unlike `thomasga`'s job-keyed
sharing above, these each get their **own new** `restic-password` secret,
deliberately not shared with `defiant`'s: this is a separate, freshly
initialized restic repository per job once the appliance services actually run
here, not a continuation of `defiant`'s live backups. See
[docs/smart-home.md § Migration: defiant → reliant](../../docs/smart-home.md#migration-defiant--reliant).

## Secrets

`hosts/reliant/secrets.nix` declares, beyond the Phase 1 SSH/NAS entries, five
secrets — **all of them reused from `defiant`'s existing `.age` files**, none
newly created. Four are named for what they hold or which hardware they're
tied to, not for `defiant` (see
[docs/secrets.md § Shared hardware and domain secrets](../../docs/secrets.md#shared-hardware-and-domain-secrets)):

- `traefik/cloudflare-api-token` — just an API credential, not tied to either
  host's identity.
- `zigbee/network-key` — matched to the physical coordinator's own NVRAM,
  not the host; reusing it is what lets already-paired Zigbee devices keep
  working without a re-pair once the coordinator moves.
- `location/coordinates` — home-address coordinates, not host- or
  radio-specific.
- `zwave/secrets` — matched to the physical controller's own NVM, same
  reasoning as the Zigbee key: reusing it avoids forcing an unnecessary
  re-pair of every Z-Wave device once the controller moves.
- `hass/restic-password`, `zigbee2mqtt/restic-password`,
  `zwave-js/restic-password` — restic-password secrets are job-keyed, not
  machine-keyed (docs/secrets.md § Secret Inventory), and the restic repo
  path already includes the hostname, so sharing the password doesn't
  collide the two hosts' backup data — same pattern as `thomasga`'s job
  above.

`reliant` isn't yet a recipient of any of these — until `secrets-warden`
widens the recipient lists in `secrets/secrets.nix` and rekeys,
`hosts/reliant/configuration.nix` will not evaluate (Nix path literals require
the referenced file to exist). That is expected at this point in the
migration, not a bug — see
[docs/smart-home.md § Migration: defiant → reliant](../../docs/smart-home.md#migration-defiant--reliant).

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
  after the fact. This PR's own secrets are a separate, still-pending
  hand-off — see § Secrets above.
- The LUKS passphrase prompt in `install.py` is vestigial for this host —
  disko has no LUKS here, the value is unused.
- The machine has been physically installed and first-booted. The SSH host
  key is pinned in `lib/ssh-hosts.nix`, and the reserved LAN IP
  (`192.168.20.15`) is confirmed against its Unifi DHCP reservation.
- No `homeConfigurations."thomasga@reliant"` entry exists in `flake.nix` yet
  — it would import `hosts/reliant/home/thomasga.nix`, which doesn't exist.
  `user-provisioner` adds both together when attaching a user (Phase 2).
