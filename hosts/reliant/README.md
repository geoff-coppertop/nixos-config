# reliant

**Phase 1 only.** This host is defined and ready for physical installation,
but carries no homelab or smart-home service module yet. It is intended to
eventually replace `defiant` as the homelab server; that migration is Phase 2
— one or more separate PRs owned by `homelab-network` and `smart-home` (see
[docs/homelab-network.md](../../docs/homelab-network.md) and
[docs/smart-home.md](../../docs/smart-home.md)) — and must not merge before
this Phase 1 PR has merged and the machine is confirmed up per
[docs/provisioning.md § Step 7](../../docs/provisioning.md#step-7--post-install-checklist).

Provisioning steps are the generic `disko` flow in
[docs/provisioning.md § Provision Types](../../docs/provisioning.md#provision-types)
onward (same as `enterprise-d`/`excelsior`).

## Machine Files

| File | Purpose |
| --- | --- |
| `configuration.nix` | Boot, hardware, networking, `custom.users` — Phase 1 scope only |
| `hardware.nix` | systemd-boot, EFI, Intel microcode, generic firmware (template, not a hardware scan — see Hardware And Access below) |
| `power.nix` | Explicit no-hibernate/no-suspend statement for this always-on headless host |
| `disko.nix` | GPT layout: ESP, swap, plain ext4 root (no btrfs/snapper — see the comment in the file for why) |
| `default.nix` | Imports `configuration.nix` only — no home-manager user attached yet |
| `secrets.nix` | `age.secrets` declarations for this host (near-empty until Step 2 enrollment) |
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
- Reserved LAN IP `192.168.20.11` — **TEMPORARY placeholder**, distinct from
  `defiant`'s own reservation (`192.168.20.10`, which stays with `defiant`
  until the Phase 2 cutover). Confirm this against the actual Unifi DHCP
  reservation once the machine is on the network and correct
  `configuration.nix` if it doesn't match. Not yet consumed by any
  `custom.*` option — no DNS or other service module is enabled in this
  Phase 1 PR.
- Headless. `profiles/desktop` is deliberately **not** imported — there is no
  display server. `profiles/dev` is also not imported — Phase 2 will decide
  whether it's needed once the actual service set (migrated from `defiant`)
  is known.
- SSH key only: `PasswordAuthentication`, `KbdInteractiveAuthentication`, and
  `PermitRootLogin` are all off.
- `security.sudo.wheelNeedsPassword = false`, same reasoning as `defiant` and
  `excelsior`: the authorized-key check is the real access gate, and a sudo
  password on top of it only blocks unattended `nixos-rebuild --target-host`
  deploys.
- `reliant` alone isn't resolvable until DNS is wired up in Phase 2 — use the
  mDNS `.local` name:

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

`custom.backups` is intentionally **not** enabled in this Phase 1 PR — same
as `excelsior`'s initial provisioning. The module asserts at least one entry
under `custom.backups.users`, and per-person home-directory entries are
`user-provisioner`'s (see
[docs/backups.md § How Backups Run](../../docs/backups.md#how-backups-run)).
Wire it up once a user or a Phase 2 service is actually running here.

## Provisioning

See [docs/provisioning.md](../../docs/provisioning.md) (the generic `disko`
flow, Steps 1–7) for the full enroll → install → first-boot process.
Host-specific notes:

- Step 1 (this PR) is done: `hosts/reliant/` is defined and registered in
  `flake.nix` as `nixosConfigurations."reliant"`.
- Step 2 (enrollment, `secrets-warden`'s hand-off) is **not** done yet:
  `hosts/reliant/secrets.nix` is pre-created with an empty `age.secrets`
  block, so `tools/enroll.py reliant` will **not** auto-add the
  `thomasga/ssh-id-ed25519-reliant` entry to it (it only does that when the
  file doesn't already exist) — add that entry by hand after running
  enroll.py, or delete the file first and let enroll.py regenerate it.
- The LUKS passphrase prompt in `install.py` is vestigial for this host —
  disko has no LUKS here, the value is unused.
- Pin the SSH host key after first boot:
  `ssh-keyscan -t ed25519 reliant.local` → `publicKey` in
  `lib/ssh-hosts.nix`.
- No `homeConfigurations."thomasga@reliant"` entry exists in `flake.nix` yet
  — it would import `hosts/reliant/home/thomasga.nix`, which doesn't exist.
  `user-provisioner` adds both together when attaching a user (Phase 2).
