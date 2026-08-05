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
| `sd-card` | `defiant` | SD card | `nix run .#install` builds and flashes the aarch64 SD image |
| `wsl` | `holodeck-01` | none | Not currently automated — see [hosts/holodeck-01/README.md](../hosts/holodeck-01/README.md) |

`nix run .#install` (`tools/install.py`) presents a machine menu and dispatches
on that provision type, so the same entry point covers both media paths.
`nix run .#provision` (`tools/provision.py`) is the lower-level driver
`install.py` calls to perform the per-type work.

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
[docs/secrets.md § Secret Inventory](secrets.md#secret-inventory). For `defiant`
in particular, the Zigbee and Z-Wave security keys **must** exist before the
first deploy; generating them later forces a re-pair of every device.

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

This repo uses lanzaboote.

1. Ensure the installed system has `/etc/secureboot` populated with your Secure
   Boot keys.
2. Rebuild the system.
3. Enroll the keys in firmware.
4. Turn Secure Boot on in UEFI.
5. Reboot and verify the system boots through the signed path.

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

## SD-Card Hosts (`defiant`)

`defiant` is a headless aarch64 Raspberry Pi 4. Machine-specific facts, service
URLs, and pairing quirks live in
[hosts/defiant/README.md](../hosts/defiant/README.md); the service architecture
is documented in [docs/homelab-network.md](homelab-network.md).

### Build and flash the SD card

After completing step 2 (enrollment, service secrets, rekey, commit, push):

```bash
nix run .#install
# Select: defiant
```

This cross-compiles the SD image (several minutes), decompresses it, prompts for
and confirms the target device before flashing, then installs `defiant`'s age
identity (`~/.config/agenix/defiant.age`, generated during enrollment) onto the
image so it can decrypt its secrets at first boot. It unmounts and powers off the
device automatically when finished — safe to remove as soon as the tool exits, no
manual eject needed.

### First boot and network setup

1. Connect ethernet, insert the SD card, power on. Wait about two minutes.
2. In the Unifi console → Clients, find `defiant` by hostname or MAC. Note the IP.
3. Set a DHCP reservation for its MAC address, giving it a fixed LAN IP.
4. Set that reserved IP as DNS Server 1 in the LAN DHCP settings.
5. Collect the SSH host key and pin it:

   ```bash
   ssh-keyscan -t ed25519 <defiant-ip> 2>/dev/null
   # Verify: ssh thomasga@<defiant-ip> "ssh-keygen -l -f /etc/ssh/ssh_host_ed25519_key.pub"
   # Paste the verified key into lib/ssh-hosts.nix as publicKey = "ssh-ed25519 AAAA..."
   ```

6. Update `lanIp` in `hosts/defiant/configuration.nix` with the reserved IP.
   Commit and push.

### First full deploy

```bash
nixos-rebuild switch --flake .#defiant \
  --target-host thomasga@defiant.local \
  --sudo
```

The bare hostname isn't resolvable — use the mDNS `.local` name. `--sudo`, not
the deprecated `--use-remote-sudo`. Every headless host sets
`security.sudo.wheelNeedsPassword = false;` (the SSH key check is the real
access gate), so no interactive password prompt.

Zigbee2MQTT and Z-Wave JS start up using the keys created during enrollment — no
further extraction step is needed.

Then complete the per-service setup in
[hosts/defiant/README.md § First-Time Service Setup](../hosts/defiant/README.md#first-time-service-setup).

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
