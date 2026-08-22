# Provisioning a Machine

The workflow to install a machine defined in this repo. The repo handles all
configuration; you provide the physical machine and initial boot media.

Complete [docs/operations.md § Workstation Setup](operations.md#workstation-setup)
once before doing any of this.

## Provision Types

Each host declares how it is provisioned in `hosts/<machine>/provision-type`:

| Type | Hosts | Media | Installer |
| --- | --- | --- | --- |
| `disko` | `enterprise-d`, `excelsior` | NixOS installer USB | `tools/install.py` runs disko, then `nixos-install` |
| `sd-card` | none currently | SD card | `nix run .#install` builds and flashes the aarch64 SD image |
| `wsl` | `holodeck-01` | none | Not currently automated — see [hosts/holodeck-01/README.md](../hosts/holodeck-01/README.md) |

`nix run .#install` (`tools/install.py`) presents a machine menu and dispatches
on that provision type, so the same entry point covers both media paths.
`nix run .#provision` (`tools/provision.py`) is the lower-level driver
`install.py` calls to perform the per-type work.

## Two Phases

Bringing up a machine is always two phases, and they are separate PRs:

- **Phase 1 — Machine Provisioning** (this document, Steps 1-7 below): get the
  machine installed, on the network, reachable over SSH, and enrolled in
  backups and secrets. Nothing else.
- **Phase 2 — Application Provisioning**: everything that makes the machine
  useful for a person or a service — desktop or dev capability, home-manager
  user environments, homelab or smart-home service modules. See
  [Phase 2 — Application Provisioning](#phase-2--application-provisioning)
  below.

Phase 1 and Phase 2 are always separate PRs — never bundled together. Phase 2
work can start any time, including in parallel with Phase 1, but a Phase 2 PR
must not merge before its Phase 1 PR has merged and the machine is confirmed
up — Phase 2 assumes the machine is already up per the Phase 1 checklist. This
keeps a new machine's first PR provably minimal: reviewable purely as "does
this box boot, join the network, and back itself up," with no capability or
service-module changes mixed in.

## Phase 1 — Machine Provisioning

In scope:

- OS install (`disko`, `sd-card`, or `wsl`, per Steps 1-7 below)
- Networking already unconditional in `profiles/common`
- `services.openssh` (set per-host in `configuration.nix`)
- `custom.users` (`modules/users.nix`) — system-level Linux accounts and SSH
  authorized keys; without this nobody can log in over SSH
- agenix secrets enrollment — age identity, SSH host key pinning
  (`secrets-warden`'s hand-off, Step 2 below)
- `custom.backups` (`modules/backups.nix`) — not optional; `profiles/common/base.nix`
  asserts it's enabled, so a host missing this fails to evaluate rather than
  just being a review gap (see [docs/backups.md](backups.md))

Out of scope — these are Phase 2, added in later, separate PRs by their owning
agent:

- `profiles/desktop` and `profiles/dev` (machine capability — see
  [docs/workstation.md](workstation.md))
- home-manager user environments — dotfiles, shell, per-user apps (see
  [docs/users.md](users.md))
- any other `custom.*` service module: homelab DNS/Traefik
  ([docs/homelab-network.md](homelab-network.md)), Home Assistant/Zigbee/Z-Wave/
  MQTT/ADS-B ([docs/smart-home.md](smart-home.md)), Wi-Fi, network drives,
  gaming, Flatpak, and so on

A new host's Step 1 files (`configuration.nix`, `default.nix`) must import
only what this list requires. Do not import `profiles/desktop` or
`profiles/dev`, and do not enable any service module beyond `custom.users` and
`custom.backups`, when defining a brand-new host. `default.nix` gets an
empty or minimal `home-manager.users` block — filling it in is
`user-provisioner`'s hand-off, same shape as the Step 2 hand-off to
`secrets-warden` below.

## Step 1 — Define the Machine in the Repo

Skip this step if the machine already exists in the repo.

1. Create `hosts/<machine-name>/`.
2. Add `hosts/<machine-name>/configuration.nix` (imports hardware, power, disk).
3. Add `hosts/<machine-name>/hardware.nix` (hardware-scan output).
4. Add `hosts/<machine-name>/power.nix` (power and hibernate policy).
5. Add `hosts/<machine-name>/disko.nix` (disk layout, if provisioning from this
   repo).
6. Add `hosts/<machine-name>/default.nix` attaching home-manager for each user.
7. Register the machine in `flake.nix` under `nixosConfigurations`:

```nix
nixosConfigurations."<machine-name>" = mkNixosSystem {
  system = "x86_64-linux"; # or "aarch64-linux" for ARM machines
  extraModules = [
    ./hosts/<machine-name>
    # add machine-specific modules as needed:
    # disko.nixosModules.disko            (physical machines with declarative disk layout)
    # lanzaboote.nixosModules.lanzaboote  (Secure Boot)
    # nixos-wsl.nixosModules.default      (WSL machines)
  ];
};
```

`mkNixosSystem` is defined in `lib/nixos-system.nix` — see
[docs/architecture.md § Where home-manager Attaches](architecture.md#where-home-manager-attaches)
for what it wires in automatically.

## Step 2 — Enroll the Machine

Enrollment generates the machine's age identity and SSH login keypair and wires
both into the repo:

```bash
nix develop -c python3 tools/enroll.py <machine-name>
```

See [docs/secrets.md § Generate SSH Login Credentials](secrets.md#generate-ssh-login-credentials)
for exactly what it does, and
[docs/secrets.md § Generating Age Identities](secrets.md#generating-age-identities)
if you need to create identities by hand instead.

Rekeying requires the offline admin key, which lives only in Bitwarden. Place it
temporarily, rekey, then shred it:

```bash
mkdir -p ~/.config/agenix && chmod 700 ~/.config/agenix
# Paste the private key from Bitwarden into ~/.config/agenix/admin.age, then:
chmod 600 ~/.config/agenix/admin.age
nix run .#secret-rekey
shred -u ~/.config/agenix/admin.age
```

Create any service secrets the machine needs before its first boot — see
[docs/secrets.md § Secret Inventory](secrets.md#secret-inventory). For a host
running Zigbee2MQTT or Z-Wave JS in particular, the Zigbee and Z-Wave security
keys **must** exist before the first deploy; generating them later forces a
re-pair of every device.

Commit and push before installing — `system.autoUpgrade` and remote deploys both
read from the GitHub remote.

## Step 3 — Write the Installer USB (`disko` hosts)

Preferred method:

1. Download the latest NixOS graphical ISO for `x86_64-linux` from the
   [NixOS download page](https://nixos.org/download.html).
2. Verify the checksum against the release page.
3. Write it to USB with Fedora Media Writer or a similar tool.

Alternative manual method:

1. Identify your USB device with `lsblk`.
2. Unmount any mounted partitions on that device.
3. Write the ISO directly, to the device and not a partition:

   ```bash
   sudo dd if=./nixos-graphical.iso of=/dev/sdX bs=4M status=progress oflag=sync
   ```

## Step 4 — Boot the Machine From USB

1. Insert the USB stick.
2. Power on the machine and open the boot menu.
3. Boot the NixOS installer USB in UEFI mode.
4. Leave Secure Boot off for the first install. It is enabled later through
   lanzaboote, once the system is installed.

**Do not use the graphical installer.** When the desktop appears, open a
terminal — the installer script in step 5 handles the full install.

## Step 5 — Run the Installer

Have ready:

- The target disk device name (`lsblk`, e.g. `/dev/nvme0n1`)
- The LUKS passphrase you want to use for disk encryption
- A second USB drive holding the machine's age identity file (optional — the key
  can be installed after the fact)

The stock installer ISO ships with flakes disabled, so fetch and run the
installer through `nix-shell` (the classic, non-flake CLI, which needs no extra
flags on a stock ISO) rather than `nix run`. `install.py` clones the full repo to
`/tmp/nixos-config` and re-execs itself from there if it does not find its
sibling modules alongside it, so this is the entire command — no separate clone
step:

```bash
nix-shell -p python3 git --run \
  'python3 <(curl -fsSL https://raw.githubusercontent.com/geoff-coppertop/nixos-config/master/tools/install.py)'
```

It prompts for a machine from the menu, then automatically:

1. Clones the repo to `/tmp/nixos-config` and re-runs itself from there
2. Enrolls the machine if it is not already enrolled (age identity and SSH host
   key) — prompts inline
3. Lists disks and prompts for the target device and LUKS passphrase
4. Prompts for an age identity key source (USB drive, file path, or skip)
5. Secures the live `nixos` session
6. Runs disko to partition, format, and mount the disk
7. Copies the repo into `/mnt/etc/nixos/nixos-config`
8. Installs the age identity key, if provided
9. Generates Secure Boot keys under `/mnt/etc/secureboot`
10. Runs `nixos-install`

**Warning:** disko destroys all data on the target disk.

The LUKS passphrase you enter unlocks the disk whenever TPM auto-unlock is
unavailable. Store it in Bitwarden before proceeding.

## Step 6 — Enroll Secure Boot

This repo uses lanzaboote, in its manual mode — `modules/secure-boot.nix` sets
`pkiBundle = "/etc/secureboot"` but does not set
`boot.lanzaboote.autoGenerateKeys.enable` or `autoEnrollKeys.enable`, so
nothing enrolls keys for you. Verified against the pinned `lanzaboote` rev
(`flake.nix`, currently `v1.1.0`)'s own docs and source.

1. Ensure the installed system has `/etc/secureboot` populated with your Secure
   Boot keys (`tools/install.py` does this at Step 5, via `sbctl create-keys`).
2. Rebuild the system so lanzaboote signs the current generation's boot files,
   then check the signature:

   ```bash
   sudo sbctl verify
   ```

   Every file should show as signed except ones starting with `kernel-` — that
   one is expected to stay unsigned.

3. **`sbctl` does not know where the keys are by default — point it there
   explicitly.** Only `autoGenerateKeys`/`autoEnrollKeys` make lanzaboote write
   `/etc/sbctl/sbctl.conf` (`nix/modules/lanzaboote.nix`:
   `environment.etc."sbctl/sbctl.conf" = lib.mkIf (cfg.autoGenerateKeys.enable
   || cfg.autoEnrollKeys.enable) ...`); this repo doesn't set either, so that
   file never exists here, and a bare `sbctl` invocation silently falls back to
   its own default, `/var/lib/sbctl` — not `/etc/secureboot`, where this repo's
   keys actually live. Every `sbctl` command below needs `--config` pointed at
   a file with the right paths:

   ```bash
   printf 'keydir: /etc/secureboot/keys\nguid: /etc/secureboot/GUID\n' | sudo tee /tmp/sbctl.conf
   sudo sbctl --config /tmp/sbctl.conf status
   ```

4. Put the firmware into Secure Boot Setup Mode. Steps vary by vendor — see the
   target host's own README for hardware-specific instructions (for example,
   [hosts/enterprise-d/README.md § Secure Boot](../hosts/enterprise-d/README.md#secure-boot)
   for Framework laptops).
5. Enroll the keys:

   ```bash
   sudo sbctl --config /tmp/sbctl.conf enroll-keys --microsoft
   ```

   Include the vendor's OEM certificates (`--microsoft`) unless you know you
   don't need them — some OptionROMs are only signed with those. On hardware
   that ships pre-provisioned firmware keys (Framework laptops are the
   documented case), add `--firmware-builtin` too, to keep those keys for
   vendor firmware updates — confirmed in lanzaboote's own
   `docs/getting-started/enable-secure-boot.md`.
6. Turn Secure Boot enforcement on in UEFI.
7. Reboot and verify:

   ```bash
   bootctl status | grep -i "secure boot"
   ```

   Expect `Secure Boot: enabled (user)`. `enabled (setup)` means the firmware
   never left Setup Mode; `disabled` means the UEFI toggle itself is still
   off. Both read the same firmware `SecureBoot` EFI variable that the
   lanzaboote UEFI stub checks at boot (`rust/uefi/stub/src/thin.rs`) — if the
   stub warns `Secure Boot is not active!` on boot, this command will not show
   `enabled (user)` either; they can't disagree.

Keep copies of Secure Boot key material in a safe recovery location. Bitwarden is
a reasonable place for the recovery instructions and escrowed material if that
matches your threat model.

## Step 7 — Post-Install Checklist

For `enterprise-d`, the canonical checklist is
[hosts/enterprise-d/README.md § Post-Install Checklist](../hosts/enterprise-d/README.md#post-install-checklist).

In general, after first boot:

1. Enroll TPM2 for LUKS auto-unlock, if the host uses it — see
   [Disk Encryption And TPM](#disk-encryption-and-tpm) below
2. Collect the SSH host public key and pin it in `lib/ssh-hosts.nix` — see
   [docs/secrets.md](secrets.md#collect-and-pin-the-host-key-after-deploy)
3. Verify the age identity is wired:
   `nix eval .#nixosConfigurations.<machine>.config.age.identityPaths --json`
4. Run the checks in
   [docs/operations.md § Validation Commands](operations.md#validation-commands)

Phase 1 is done once this checklist passes and the Phase 1 PR has merged.

## Phase 2 — Application Provisioning

Everything that is not required to get the machine up, on the network, and
backed up. Opened as one or more separate PRs, never bundled into the Phase 1
PR. Phase 2 work can start any time, but a Phase 2 PR must not merge before
the Phase 1 PR has merged and the machine is confirmed up (this checklist
passed) — Phase 2 assumes the machine is already up.

Each concern below is owned by one agent:

- **Machine capability** — opting the host into `profiles/desktop` or
  `profiles/dev`: `machine-provisioner`'s own domain, see
  [docs/workstation.md](workstation.md)
- **A person's environment on this machine** — attaching home-manager,
  dotfiles, per-user apps: `user-provisioner`, see [docs/users.md](users.md)
- **Homelab reverse proxy and DNS** — Traefik, AdGuard, unbound:
  `homelab-network`, see [docs/homelab-network.md](homelab-network.md)
- **Homelab appliance layer** — Home Assistant, Zigbee, Z-Wave, Matter, MQTT,
  ADS-B: `smart-home`, see [docs/smart-home.md](smart-home.md)

Ownership is not the same as PR count. By default, open a separate PR per
concern — that's what keeps an unrelated, independently timed change
reviewable on its own. But when several of these concerns target the *same*
new host as one coordinated migration happening in the same sitting (for
example, bringing up both the DNS/Traefik and appliance layers on a
replacement host at once), splitting them into separate PRs buys nothing:
both are guaranteed to touch the same new files and conflict with each other
on merge, for no independent-review benefit. In that case, combine them into
one PR with each owning agent contributing its own section, and say so in the
PR description. Default to splitting; combine only when the concerns are
genuinely one coordinated change, not several unrelated ones that happen to
land around the same time.

If a new host needs a genuinely new kind of module or profile that doesn't
exist yet, that design question is `architect`'s, per
[docs/architecture.md](architecture.md).

## Disk Encryption And TPM

`enterprise-d` encrypts the root filesystem with LUKS and seals it to the
machine's TPM 2.0 chip.

### The LUKS passphrase

The disko configuration creates an encrypted root partition. `tools/install.py`
prompts for a LUKS passphrase interactively during provisioning (Step 5). That
passphrase unlocks the root filesystem whenever the TPM is unavailable or
tampered with.

Save it in Bitwarden or another secure location **outside** the machine. You will
need it if:

- The TPM is reset or replaced
- The firmware is updated and TPM state is cleared
- You boot from a rescue USB and need to unlock the disk manually

### Enrolling and verifying the TPM

The enrollment and verification commands, including the PCR selection and what
each PCR measures, live in
[hosts/enterprise-d/README.md](../hosts/enterprise-d/README.md#tpm-auto-unlock).
That is the canonical copy.

### Change or reset the LUKS passphrase

To change the passphrase while the system is running:

```bash
sudo cryptsetup luksChangeKey /dev/disk/by-partlabel/root
```

To wipe the passphrase slot and rely entirely on TPM2 unlock:

```bash
sudo systemd-cryptenroll /dev/disk/by-partlabel/root --wipe-slot=password
```

### TPM recovery and troubleshooting

If the system does not auto-unlock at boot:

1. **At the initrd prompt** you will be asked for the LUKS passphrase. Enter the
   passphrase you created during install.
2. **If you forgot the passphrase**, boot from a NixOS rescue USB and use
   standard LUKS recovery tools.
3. **If the TPM appears broken**, re-enroll the passphrase and optionally
   re-enroll TPM2 after the system boots.
4. **If Secure Boot or firmware state changed**, the TPM may not unlock
   automatically. Either provide the passphrase or re-enroll TPM after boot.

## SD-Card Hosts

No current host uses `sd-card` provisioning — the aarch64 homelab server this
path was built for (`defiant`) has been retired in favor of `reliant`
(`x86_64-linux`, generic `disko` provisioning). The mechanism below is kept
documented for a future aarch64 host, since the tooling
(`tools/provision.py`, `tools/install.py`) is already generic and
machine-name-parametrized, not tied to any specific host.

Machine-specific facts (service URLs, pairing quirks) for a headless aarch64
host of this kind would live in that host's own README, following the
pattern of `hosts/reliant/README.md`; the service architecture is documented
in [docs/homelab-network.md](homelab-network.md).

### Build and flash the SD card

After completing step 2 (enrollment, service secrets, rekey, commit, push):

```bash
nix run .#install
# Select: <machine>
```

This cross-compiles the SD image (several minutes), decompresses it, prompts for
and confirms the target device before flashing, then installs `<machine>`'s age
identity (`~/.config/agenix/<machine>.age`, generated during enrollment) onto the
image so it can decrypt its secrets at first boot. It unmounts and powers off the
device automatically when finished — safe to remove as soon as the tool exits, no
manual eject needed.

### First boot and network setup

1. Connect ethernet, insert the SD card, power on. Wait about two minutes.
2. In the Unifi console → Clients, find `<machine>` by hostname or MAC. Note the IP.
3. Set a DHCP reservation for its MAC address, giving it a fixed LAN IP.
4. Set that reserved IP as DNS Server 1 in the LAN DHCP settings, if this host
   is meant to serve DNS.
5. Collect the SSH host key and pin it:

   ```bash
   ssh-keyscan -t ed25519 <machine-ip> 2>/dev/null
   # Verify: ssh thomasga@<machine-ip> "ssh-keygen -l -f /etc/ssh/ssh_host_ed25519_key.pub"
   # Paste the verified key into lib/ssh-hosts.nix as publicKey = "ssh-ed25519 AAAA..."
   ```

6. Update `lanIp` in `hosts/<machine>/configuration.nix` with the reserved IP.
   Commit and push.

### First full deploy

```bash
nixos-rebuild switch --flake .#<machine> \
  --target-host thomasga@<machine>.local \
  --sudo
```

The bare hostname isn't resolvable — use the mDNS `.local` name. `--sudo`, not
the deprecated `--use-remote-sudo`. Every headless host sets
`security.sudo.wheelNeedsPassword = false;` (the SSH key check is the real
access gate), so no interactive password prompt.

An SD card is fixed-size — unlike `enterprise-d`/`excelsior`'s NVMe/SSD, there
is no headroom to grow into. Check free space before a large deploy:

```bash
ssh thomasga@<machine>.local "df -h /"
```

Cap boot generations (`boot.loader.generic-extlinux-compatible.configurationLimit`)
and this host's `custom.nix.gc.keepGenerations` override (a per-host override
of `profiles/common/base.nix`'s option, shared default: 10) well below the
default on a small card — `defiant`'s own 30G card needed both dropped to 3
before a full `nix-collect-garbage -d` (which also drops all old generations)
reliably kept it under its ~23-24G floor; treat that as a per-host example to
tune from, not a default to copy verbatim. Also consider scoping
`nix.settings.min-free`/`max-free` to the host so a build or deploy triggers
proactive GC mid-operation instead of failing outright. If `df -h` still shows
the root partition nearly full, it's Nix store garbage (unreferenced paths,
not kept generations): run `nix-collect-garbage -d` on the host, or wait for
the nightly `nix-gc` timer.

If the host runs Zigbee2MQTT and/or Z-Wave JS, they start up using the keys
created during enrollment — no further extraction step is needed.

## WSL Hosts (`holodeck-01`)

Fresh WSL bootstrap is **not currently available**. `install.py`'s WSL flow
(fetch NixOS-WSL, `wsl --import`, apply the flake) was pulled out of the Python
tooling rewrite pending real validation — unlike the disko flow, it had never
been run end to end. It will return in a follow-up once there is an environment
to validate it against, or may not return at all if WSL usage here winds down as
expected.

If you need to bootstrap a **new** WSL machine before that lands, ask first
rather than reaching for old instructions — nothing in this repo currently
automates it.

Rebuilding the existing instance is unaffected — see
[hosts/holodeck-01/README.md](../hosts/holodeck-01/README.md).
