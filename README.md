# NixOS Config

This repo is the source of truth for machine setup, user setup, secrets wiring, and update policy. There are two main tasks it supports: provisioning a machine already defined here, and adding an entirely new machine to the repo.

## Contents

- [Repository Model](#repository-model)
- [Setup](#setup)
  - [Prerequisites](#prerequisites)
  - [Setting Up On Non-NixOS Linux Or WSL](#setting-up-on-non-nixos-linux-or-wsl)
  - [Verifying Your Setup](#verifying-your-setup)
  - [Dev Shell And Repo Tools](#dev-shell-and-repo-tools)
- [Provisioning a Machine](#provisioning-a-machine)
  - [Create a NixOS Installer USB](#create-a-nixos-installer-usb)
  - [SSH Management](#ssh-management)
  - [Collect Host SSH Public Key After Deploy](#collect-host-ssh-public-key-after-deploy)
  - [Backups](#backups)
  - [Boot the Machine From USB](#boot-the-machine-from-usb)
  - [Run the Installer Script From the Live Session](#run-the-installer-script-from-the-live-session)
  - [Enroll Secure Boot After Install](#enroll-secure-boot-after-install)
  - [Post-Install Validation](#post-install-validation)
- [Defining a New Machine](#defining-a-new-machine)
  - [Repository Structure](#repository-structure)
  - [Secrets and SSH Setup](#secrets-and-ssh-setup)
- [Reference](#reference)
  - [Secrets Management](#secrets-management)
  - [Wi-Fi Pre-configuration](#wi-fi-pre-configuration)
  - [Hibernation And Power](#hibernation-and-power)
  - [Updating The System](#updating-the-system)
  - [Users And Configuration](#users-and-configuration)
  - [Dotfiles And Shell Scripts](#dotfiles-and-shell-scripts)
  - [Desktop Application Policy](#desktop-application-policy)
  - [Validation Commands](#validation-commands)

## Repository Model

The repo is split by responsibility.

- `hosts/<machine>/` owns machine-specific hardware, power, and disk layout.
- `roles/` owns shared system policy such as base settings, networking, and the desktop baseline.
- `modules/` owns reusable system features such as btrfs, secrets, and secure boot.
- `users/<name>/` owns personal applications, dotfiles, shell behavior, and workflow tooling through home-manager.
- `secrets/` owns agenix-encrypted material that is safe to commit.

Use this rule when placing configuration:

- If it affects machine operation, put it in the system layer: `hosts/<machine>/` for machine-specific behavior, `roles/` for shared system policy, or `modules/` for reusable NixOS features.
- If it affects a person's workflow, put it in that user's home-manager config under `users/<name>/`, usually in `users/<name>/default.nix` or a user module imported from there.
- If several users may want it, create a reusable opt-in user module under `users/common/` and let each user import it from `users/<name>/default.nix` instead of forcing it globally.

The active machine in this repo is `framework` — see [hosts/framework/FRAMEWORK.md](hosts/framework/FRAMEWORK.md) for machine-specific files, installation checklist, and power behaviour.

## Setup

This section is mandatory before doing any provisioning or defining new machines. Complete it once per development environment.

### Prerequisites

You need Nix (version 2.18+) with flakes enabled. If working on Ubuntu, Fedora, Debian, or WSL, follow the setup guide below. On a NixOS system, these should already be configured.

**Checklist:**

- [ ] Nix is installed (from an official or up-to-date installer)
- [ ] Nix version is 2.18 or later: `nix --version`
- [ ] Flakes are enabled in `~/.config/nix/nix.conf`: `experimental-features = nix-command flakes`
- [ ] You've started a fresh shell after any installer/config changes
- [ ] Multi-user installs have you in the `nix-users` group: `id -Gn | grep nix-users`

### Setting Up On Non-NixOS Linux Or WSL

If the checklist above isn't complete, follow these steps:

1. Install Nix with an official multi-user installer. Avoid distro packages if they lag far behind upstream. Start a fresh login shell afterward.
2. Enable flakes and the modern Nix CLI:

   ```bash
   mkdir -p ~/.config/nix
   printf 'experimental-features = nix-command flakes\n' >> ~/.config/nix/nix.conf
   ```

3. For WSL specifically: run commands inside the Linux filesystem and keep the age identity under `~/.config/agenix/` in the Linux home directory.
4. If the daemon socket permission fails, fully log out and log back in. On systemd systems, verify `nix-daemon.service` is running.

### Verifying Your Setup

Run these checks to confirm everything is working:

```bash
cd /home/thomasg/builds/geoff-coppertop/nixos-config
nix --version                          # should be 2.18+
id -Gn | grep nix-users                # multi-user only
nix flake metadata path:$PWD           # verify flake resolution
nix develop -c bash -lc 'command -v age agenix pre-commit alejandra statix deadnix markdownlint'
```

All commands should succeed. The final one verifies the dev shell includes `age`, `agenix`, and all lint tools.

### Dev Shell And Repo Tools

Enter the development shell:

```bash
cd /home/thomasg/builds/geoff-coppertop/nixos-config
nix develop
```

Use these helper commands instead of invoking `agenix` directly:

```bash
nix run .#secret-edit -- secrets/thomasga/restic-password.age
nix run .#secret-rekey
```

Run checks before submitting changes:

```bash
nix develop -c pre-commit run --all-files
nix flake check
```

The pre-commit configuration checks:

- `alejandra` for Nix formatting
- `statix` for Nix linting
- `deadnix` for unused Nix code
- `markdownlint` for Markdown docs
- `no-plaintext-secrets` to block plaintext secret files

## Provisioning a Machine

This is the standard workflow to install a machine already defined in this repo (such as `framework`). The repo handles all configuration; you provide the physical machine and initial boot media.

### Create a NixOS Installer USB

Run these steps from your Linux or WSL shell after verifying setup above.

1. Enter the repo shell:

   ```bash
   cd /home/thomasg/builds/geoff-coppertop/nixos-config
   nix develop
   ```

   Confirm the secret tooling is present:

   ```bash
   command -v age
   command -v agenix
   printf '%s\n' "$EDITOR"
   ```

   If `EDITOR` is empty, set it before using `nix run .#secret-edit`. Either prefix it inline:

   ```bash
   EDITOR=nano nix run .#secret-edit -- secrets/thomasga/restic-password.age
   ```

   Or export it for the rest of the session:

   ```bash
   export EDITOR=nano
   ```

2. Generate the offline admin age identity outside the repo:

   ```bash
   mkdir -p ~/.config/agenix
   chmod 700 ~/.config/agenix
   age-keygen -o ~/.config/agenix/admin.age
   chmod 600 ~/.config/agenix/admin.age
   ```

3. Generate the host-specific age identity for the initial machine in this repo:

   ```bash
   age-keygen -o ~/.config/agenix/framework.age
   chmod 600 ~/.config/agenix/framework.age
   ```

4. Copy the public keys printed by `age-keygen` into `secrets/secrets.nix`.

   - Set `offlineAdmin` to the offline recovery key.
   - Set `framework` to the host key for `framework`.

   The checked-in secret recipients are intentionally framework-scoped. Do not add a new host as a recipient unless that host actually needs that secret.

5. Store the offline admin private key or its recovery material in Bitwarden. Do not install that key onto machines.

6. Before the first `nixos-install`, copy the host private key into the mounted target so the installed system can decrypt secrets on first boot. The installer script handles this interactively, or run it manually:

   ```bash
   sudo bash tools/install-age-identity.sh --file ~/.config/agenix/framework.age
   ```

   Pass `--shred` to erase the source file after copying.

7. On an already-installed machine, install or rotate the dedicated host identity in place with:

   ```bash
   sudo bash tools/install-age-identity.sh --file ~/.config/agenix/framework.age \
     --target /var/lib/agenix/identity
   ```

#### Creating Or Rotating Secrets

Never create plaintext files under `secrets/`. Use the helper command so the plaintext only exists in a temporary editor buffer.

For a brand-new secret:

1. Add a recipient entry to `secrets/secrets.nix`. Example:

   ```nix
   "thomasga/nas-smb-credentials.age".publicKeys = [framework offlineAdmin];
   ```

2. Create or edit the encrypted file:

   ```bash
   EDITOR=nano nix run .#secret-edit -- secrets/thomasga/nas-smb-credentials.age
   ```

3. If NixOS or home-manager needs a runtime path for that secret, expose it through `age.secrets` in `modules/secrets.nix` or another imported module.

   To rotate an existing secret:

   ```bash
   EDITOR=nano nix run .#secret-edit -- secrets/thomasga/restic-password.age
   ```

   After changing recipients in `secrets/secrets.nix`, re-encrypt every tracked secret with the offline admin key available locally:

   ```bash
   nix run .#secret-rekey
   ```

#### Future Host Secret Scope

When you add another host, generate a separate age identity for that host and add its public key to `secrets/secrets.nix` under a new host name. Only add that host to the recipient list for the secrets it needs. Do not widen existing recipient lists just because a new machine exists.

#### Exact Secret Contents

`secrets/thomasga/restic-password.age` decrypts to exactly one plaintext line:

```text
correct-horse-battery-staple
```

Do not add `password=`. Do not add quotes. Do not use JSON.

`secrets/thomasga/nas-smb-credentials.age` decrypts to:

```text
username=nas-user
password=nas-password
```

Each Wi-Fi secret decrypts to exactly one line:

```text
WIFI_AGT_HOME_PASSWORD=your-passphrase-here
```

Use the matching variable name for each network:

| Secret file            | Variable name             | Network    |
|------------------------|---------------------------|------------|
| `wifi/agt-home.age`    | `WIFI_AGT_HOME_PASSWORD`  | `agt-home` |
| `wifi/agt-iot.age`     | `WIFI_AGT_IOT_PASSWORD`   | `agt-iot`  |
| `wifi/agt-work.age`    | `WIFI_AGT_WORK_PASSWORD`  | `agt-work` |

Do not add quotes. Do not add any other lines.

#### What May Be Committed

Safe to commit:

- `secrets/**/*.age`
- `secrets/secrets.nix`

Never commit:

- plaintext secret files
- age private keys
- decrypted copies of secrets
- Bitwarden exports or recovery bundles

The repo is set up to make mistakes harder:

- `.gitignore` ignores common plaintext scratch files and local key material
- `pre-commit` rejects staged plaintext files under `secrets/`
- `pre-commit` rejects raw private keys anywhere in the repo

#### Download and Write the NixOS Installer USB

Preferred method:

1. Download the latest NixOS graphical ISO for `x86_64-linux` from the [NixOS download page](https://nixos.org/download.html).
2. Verify the checksum against the release page.
3. Write to USB using Fedora Media Writer or similar tool.

Alternative manual method:

1. Identify your USB device with `lsblk`.
2. Unmount any mounted partitions for that device.
3. Write the ISO directly (replace `/dev/sdX` with your device, not a partition):

   ```bash
   sudo dd if=./nixos-graphical.iso of=/dev/sdX bs=4M status=progress oflag=sync
   ```

### SSH Management

SSH trust is managed separately from agenix secrets.

- SSH login keys should be per-host keypairs.
- SSH host trust should be pinned in `lib/ssh-hosts.nix` and rendered to `programs.ssh.knownHosts` by `modules/ssh-known-hosts.nix`.
- `known_hosts` records server identity. `authorized_keys` grants login access. They are different data flows.

#### Generate SSH Login Credentials

Create an SSH keypair on your local machine and encrypt it as an agenix secret so it can be deployed consistently across machines:

```bash
cd /home/thomasg/builds/geoff-coppertop/nixos-config
bash tools/bootstrap-ssh-key.sh framework
```

This script:

1. Generates `~/.ssh/id_ed25519` (private) and `~/.ssh/id_ed25519.pub` (public)
2. Prompts you to encrypt the private key as an agenix secret
3. Shows you the exact commands to run next

**To complete the encryption:**

1. Add the secret to `secrets/secrets.nix`:

   ```nix
   "thomasga/ssh-id-ed25519.age".publicKeys = [framework offlineAdmin];
   ```

2. Encrypt the private key:

   ```bash
   EDITOR=nano nix run .#secret-edit -- secrets/thomasga/ssh-id-ed25519.age
   ```

   When the editor opens, paste the contents of `~/.ssh/id_ed25519`, save, and exit. Agenix will encrypt it automatically.

3. After encryption is complete, securely delete the unencrypted private key:

   ```bash
   shred -vfz ~/.ssh/id_ed25519
   ```

   The `shred` command overwrites the file with random data before deletion to prevent recovery.

4. The encrypted secret is now safe to commit.

   The private key will be decrypted and deployed to `~/.ssh/id_ed25519` at runtime by home-manager (already configured in `users/thomasga/ssh.nix` and `modules/secrets.nix`).

**For the Framework's authorized_keys:**

The matching public key (`~/.ssh/id_ed25519.pub`) is printed by the bootstrap script. You need to install it on the Framework so it can authenticate your logins:

1. Log into the Framework initially through another method (serial console, local login, etc.)
2. Add your public key to `~/.ssh/authorized_keys` on the Framework
3. Do not commit this public key to the repo

### Collect Host SSH Public Key After Deploy

The deployed Framework generates its own SSH host keypair automatically when sshd starts. This is separate from the login keypair above and is what remote machines use to verify they are talking to the correct host.

When the Framework boots with sshd enabled in [hosts/framework/configuration.nix](hosts/framework/configuration.nix), NixOS automatically generates the host keypair in `/etc/ssh/ssh_host_ed25519_key` and `/etc/ssh/ssh_host_ed25519_key.pub`. The private key stays on the machine unencrypted (standard SSH practice); only the public key is needed in the repo.

After the Framework boots for the first time:

1. Collect the host's SSH public key from the running machine:

   ```bash
   ssh-keyscan -t ed25519 framework 2>/dev/null
   ```

   This will print a line like:

   ```bash
   framework ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDCRCqI2...
   ```

2. Verify the fingerprint out-of-band (log in to the machine and compare `ssh-keygen -l -f /etc/ssh/ssh_host_ed25519_key.pub` to what ssh-keyscan printed).
3. Extract just the public key portion and add it to `lib/ssh-hosts.nix` in the `publicKey` field for the Framework host.

#### Pin Managed Host Keys

Add each managed host to `lib/ssh-hosts.nix` with:

- `hostName`: the real SSH hostname
- `aliases`: optional short names you want in SSH config
- `publicKey`: the verified SSH host public key
- `user`: the default SSH username

`modules/ssh-known-hosts.nix` turns that inventory into `programs.ssh.knownHosts`, and `users/thomasga/ssh.nix` provides per-host SSH match blocks through home-manager.

Verify the host key out-of-band before committing it. `ssh-keyscan` is a collection mechanism, not a trust oracle.

### Backups

`modules/backups.nix` provides client-pushed restic backups to a NAS share. The NAS is mounted on demand over SMB or NFS. Backups run on a daily timer. On hosts marked as laptops, backups only run when AC power is connected. If the NAS is unreachable, the job exits cleanly.

### How It Works

Each enabled user gets a separate systemd service (`nas-backup-<user>`) and timer (`nas-backup-<user>-timer`). The service:

1. Triggers an automount of the NAS share.
2. Exits silently if the share is not reachable.
3. Initialises a restic repository on first run.
4. Backs up the configured paths (default: `/home/<user>`, excluding `.cache`).
5. Prunes old snapshots according to the retention policy (7 daily, 4 weekly, 12 monthly, 3 yearly by default). This progressively reduces granularity over time while keeping long-term coverage.

### Enabling Backups on a Host

**1. Create the encrypted SMB credentials secret for each user.**

If the secret file is new, add a recipient entry first:

```nix
"thomasga/nas-smb-credentials.age".publicKeys = [framework offlineAdmin];
```

Then create or rotate the encrypted file:

```bash
EDITOR=nano nix run .#secret-edit -- secrets/thomasga/nas-smb-credentials.age
```

Its plaintext contents must be:

```text
username=<nas-username>
password=<nas-password>
```

And expose it at a known path in `modules/secrets.nix` or a host-specific secrets file:

```nix
age.secrets."thomasga/nas-smb-credentials".file =
  ../secrets/thomasga/nas-smb-credentials.age;
```

**2. Create or rotate the restic password secret.**

`thomasga/restic-password.age` already exists in this repo. Rotate it with:

```bash
EDITOR=vim nix run .#secret-edit -- secrets/thomasga/restic-password.age
```

Its plaintext contents must be exactly one line containing the restic password.

**3. Set the NAS coordinates and enable the module in the host configuration.**

```nix
custom.isLaptop = true;  # omit or set false for non-laptops

custom.backups = {
  enable = true;

  nas = {
    host   = "192.168.1.x";   # or hostname if DNS resolves it
    share  = "backups";        # share name on the UNAS Pro
  };

  nas.credentialsFile = "/run/agenix/thomasga/nas-smb-credentials";

  users.thomasga.enable = true;
};
```

Use `nas.protocol = "nfs"` and omit `credentialsFile` to switch to NFS instead.

**4. Rebuild the system.**

```bash
sudo nixos-rebuild switch --flake /etc/nixos/nixos-config#<hostname>
```

### Checking Backup Status

```bash
# List timers and see when next backup runs
systemctl list-timers 'nas-backup-*'

# Run a backup immediately
sudo systemctl start nas-backup-thomasga.service

# View the backup log
journalctl -u nas-backup-thomasga.service

# List restic snapshots on the NAS
sudo restic --repo /mnt/nas-backups/thomasga/<hostname> snapshots
```

### Adding a New Host

1. Import `../../modules/backups.nix` in the host's `configuration.nix`.
2. Set `custom.isLaptop` appropriately.
3. Set `custom.backups.nas.host`, `nas.share`, `nas.credentialsFile`, and enable at least one user.
4. Ensure the per-user restic password and SMB credentials secrets are declared.

### Limitations

- Backups target `/home` only. Add explicit paths such as `/var/lib/<service>` for mutable service state.
- Snapper manages local btrfs snapshots for rollback; it is not involved in NAS backups.
- If SMB is unavailable at boot, the automount fails silently and the next timer invocation will retry.

### Boot the Machine From USB

1. Insert the USB stick.
2. Power on the machine and open the boot menu.
3. Boot the NixOS installer USB in UEFI mode.
4. Leave Secure Boot off for the first install. Secure Boot is enabled later through lanzaboote after the system is installed.

**Do not use the graphical installer.** When the desktop appears, just open a terminal — the script in step 4 handles the full install.

### Run the Installer Script From the Live Session

Once booted into the NixOS installer, open a terminal and run the installer script. Have ready:

- The target disk device name (run `lsblk` to identify it, e.g. `/dev/nvme0n1`)
- The LUKS passphrase you want to use for disk encryption
- A second USB drive with the machine's age identity file (optional — see "Defining a New Machine"; you can add the key after install if needed)

The script will prompt for each of these, then automatically:

1. Secure the live `nixos` session
2. Create the target directory with restricted permissions
3. Clone the repo into `/mnt/etc/nixos/nixos-config`
4. Select the target host from the hosts available in the repo
5. Run disko to partition, format, and mount the disk
6. Optionally install the age identity key from a second USB drive (skip if you plan to add it later)
7. Run `nixos-install`

**WARNING:** disko will destroy all data on the target disk.

```bash
nix-shell -p git --run \
  'bash <(curl -fsSL https://raw.githubusercontent.com/geoff-coppertop/nixos-config/master/tools/nixos-install.sh)'
```

The LUKS passphrase you enter will be used to unlock the disk if TPM auto-unlock is ever unavailable. Store it in Bitwarden before proceeding.

### Enroll Secure Boot After Install

This repo uses lanzaboote.

1. Ensure the installed system has `/etc/secureboot` populated with your Secure Boot keys.
2. Rebuild the system.
3. Enroll the keys in firmware.
4. Turn Secure Boot on in UEFI.
5. Reboot and verify the system boots through the signed path.

Keep copies of Secure Boot key material in a safe recovery location. Bitwarden is a reasonable place for the recovery instructions and escrowed material if that matches your threat model.

### Post-Install Validation

See [hosts/framework/FRAMEWORK.md](hosts/framework/FRAMEWORK.md) for the Framework post-install checklist.

## Defining a New Machine

To add an entirely new machine to this repo:

### Repository Structure

1. Create `hosts/<machine-name>/`.
2. Add `hosts/<machine-name>/configuration.nix` (imports hardware, power, disko).
3. Add `hosts/<machine-name>/hardware.nix` (hardware-scan output).
4. Add `hosts/<machine-name>/power.nix` (power and hibernate policy).
5. Add `hosts/<machine-name>/disko.nix` (disk layout if provisioning from this repo).
6. Register the machine in `flake.nix` under `nixosConfigurations`:

```nix
nixosConfigurations.<machine-name> = nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    ./hosts/<machine-name>
    disko.nixosModules.disko
    home-manager.nixosModules.home-manager
    agenix.nixosModules.default
    lanzaboote.nixosModules.lanzaboote
  ];
};
```

### Secrets and SSH Setup

For the new machine to decrypt secrets and authenticate over SSH:

1. **Generate a host-specific age identity** (if not already available from a previous install):

   ```bash
   mkdir -p ~/.config/agenix
   age-keygen -o ~/.config/agenix/<machine-name>.age
   chmod 600 ~/.config/agenix/<machine-name>.age
   ```

2. **Add the host's public age key to `secrets/secrets.nix`**:

   ```nix
   <machine-name> = "age1...";  # from age-keygen output
   ```

   Then add recipient lists for secrets this host needs:

   ```nix
   "thomasga/restic-password.age".publicKeys = [ framework offlineAdmin <machine-name> ];
   ```

3. **Generate SSH login credentials** for this machine:

   ```bash
   bash tools/bootstrap-ssh-key.sh <machine-name>
   ```

   Follow the script's instructions to encrypt the private key as an agenix secret.

4. **Enable SSH in the host's `configuration.nix`** and add the encrypted SSH secret to `modules/secrets.nix` (see [SSH Management](#ssh-management) for details).

5. **Follow the provisioning workflow** to install the machine.

6. **Collect the SSH host public key** after first boot and add it to `lib/ssh-hosts.nix`.

## Reference

### Secrets Management

This repo uses agenix for committed secrets and Bitwarden for recovery material. Secrets live in `secrets/` and are safe to commit; only the decrypted content is sensitive.

Runtime decryption on NixOS uses the dedicated age private key at `/var/lib/agenix/identity` (configured in `modules/secrets.nix`).

#### First-Time Secret Bootstrap

This repo encrypts the root filesystem with LUKS and seals it to the TPM 2.0 chip in your Framework laptop.

#### Encryption At Install Time

The disko configuration creates an encrypted root partition. During provisioning (step 4 above), you provide a LUKS passphrase in `/tmp/encryption-password`. This passphrase will unlock the root filesystem if the TPM is unavailable or tampered with.

**Important:** Write down or save this passphrase in a secure location outside the machine. You will need it if:

- The TPM is reset or replaced
- The firmware is updated and TPM state is cleared
- You boot from a rescue USB and need to manually unlock the disk

#### TPM Auto-Unlock After Install

See [hosts/framework/FRAMEWORK.md](hosts/framework/FRAMEWORK.md) for the TPM enrollment steps, PCR selections, and verification commands.

#### Change Or Reset The LUKS Passphrase

To change the passphrase while the system is running:

```bash
sudo cryptsetup luksChangeKey /dev/disk/by-partlabel/root
```

To wipe the passphrase slot and rely entirely on TPM2 unlock:

```bash
sudo systemd-cryptenroll /dev/disk/by-partlabel/root --wipe-slot=password
```

#### TPM Recovery And Troubleshooting

If the system does not auto-unlock at boot:

1. **At the initrd prompt:** You will be asked for the LUKS passphrase. Enter the passphrase you created during install.
2. **If you forgot the passphrase:** Boot from a NixOS rescue USB and use standard LUKS recovery tools.
3. **If the TPM appears broken:** Re-enroll the passphrase and optionally re-enroll TPM2 after the system boots.
4. **If Secure Boot or firmware state changes:** The TPM may not unlock automatically. Either provide the passphrase or re-enroll TPM after boot.

Store your LUKS passphrase in Bitwarden or another secure offline location for disaster recovery.

### Wi-Fi Pre-configuration

Wi-Fi credentials are declared in `roles/common/networking.nix` using `networking.networkmanager.ensureProfiles`. The SSID is stored in plaintext in the config; the password is kept in an agenix-encrypted secret and substituted at activation time. NetworkManager writes the final profile to `/etc/NetworkManager/system-connections/` (0600, root-only) — the same location and permissions as any manually-configured connection. LUKS encryption protects these files at rest. The agenix secret itself lives on tmpfs (`/run/agenix/`) and is never written to disk.

Currently configured networks: `agt-home`, `agt-iot`, `agt-work`.

#### Creating the secrets

For each network, create its encrypted secret (run once per network):

```bash
EDITOR=nano nix run .#secret-edit -- secrets/wifi/agt-home.age
EDITOR=nano nix run .#secret-edit -- secrets/wifi/agt-iot.age
EDITOR=nano nix run .#secret-edit -- secrets/wifi/agt-work.age
```

Each file must contain exactly one line — the variable name and password with no quotes:

```text
WIFI_AGT_HOME_PASSWORD=your-passphrase-here
```

See the table in [Exact Secret Contents](#exact-secret-contents) for the variable name required by each network.

#### Adding another network

Each new network requires changes in four places:

1. **`secrets/secrets.nix`** — add a recipient entry:

   ```nix
   "wifi/newnet.age".publicKeys = [framework offlineAdmin];
   ```

2. **`modules/secrets.nix`** — expose the secret at runtime:

   ```nix
   "wifi/newnet".file = ../secrets/wifi/newnet.age;
   ```

3. **`roles/common/networking.nix`** — add the secret path to `environmentFiles` and a new profile block:

   ```nix
   environmentFiles = [
     # existing entries...
     config.age.secrets."wifi/newnet".path
   ];
   profiles."newnet-ssid" = {
     connection = {id = "newnet-ssid"; type = "wifi";};
     wifi = {ssid = "newnet-ssid"; mode = "infrastructure";};
     wifi-security = {key-mgmt = "wpa-psk"; psk = "$WIFI_NEWNET_PASSWORD";};
     ipv4.method = "auto";
     ipv6.method = "auto";
   };
   ```

   The `$WIFI_NEWNET_PASSWORD` placeholder must match the variable name in the secret file exactly.

4. **`secrets/wifi/newnet.age`** — create the encrypted secret:

   ```bash
   EDITOR=nano nix run .#secret-edit -- secrets/wifi/newnet.age
   ```

   File contents: `WIFI_NEWNET_PASSWORD=your-passphrase`

#### Verification

After `sudo nixos-rebuild switch --flake .#framework`:

```bash
nmcli connection show              # profiles should appear
sudo cat /etc/NetworkManager/system-connections/agt-home.nmconnection
```

### Hibernation And Power

Hibernation uses the dedicated swap partition (`/dev/vg/swap`). Full behaviour — scenarios, timings, and implementation notes — is documented in the host power document:

- [Framework](hosts/framework/FRAMEWORK.md)

After installation, validate hibernation with:

```bash
systemctl hibernate
```

Then verify the machine resumes correctly.

### Updating The System

This repo tracks `nixos-unstable` for GNOME and kernel updates. The real pin is `flake.lock`.

Monthly update workflow:

```bash
nix flake update
sudo nixos-rebuild dry-activate --flake .#framework
sudo nixos-rebuild switch --flake .#framework
```

After each update, test:

- boot
- GNOME login
- hibernation and resume
- Secure Boot state

If an update regresses behavior, revert `flake.lock` from git and rebuild.

### Change GNOME Or Kernel Policy Later

The current baseline comes from `nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"` in `flake.nix`.

To change the baseline later:

1. Change the `nixpkgs` input to a different branch or revision.
2. Update the lock file.
3. Rebuild and test.

That is the correct place to move between more conservative and more aggressive GNOME/kernel update policies.

### Users And Configuration

A user is fully assigned to a machine only when two pieces are present:

1. A Unix account exists in the NixOS config.
2. A matching home-manager config is attached for that host.

### Current Example: `thomasga`

System user declaration lives in `roles/common/users.nix`:

```nix
users.users.thomasga = {
  isNormalUser = true;
  extraGroups = [ "wheel" "networkmanager" ];
};
```

`wheel` is the admin group here, so this is the file to change if `thomasga` should be able to administer the Framework laptop.

Home-manager attachment lives in `flake.nix`:

```nix
home-manager.users = {
  thomasga = import ./users/thomasga;
};
```

### Add A New User

To add `alice`:

1. Create `users/alice/default.nix`.
2. Add optional user modules such as `users/alice/secrets.nix` or `users/alice/vscode.nix`.
3. Declare the Unix user in a shared or host-specific NixOS module.
4. Attach the home-manager config for each host that should include `alice`.

Concrete example:

```nix
users.users.alice = {
  isNormalUser = true;
  extraGroups = [ "wheel" "networkmanager" ];
};
```

```nix
home-manager.users.alice = import ./users/alice;
```

### Assign A User To One Host Or All Hosts

- Put the Unix account in a shared module if the user should exist on all hosts.
- Put the Unix account in a host-specific import if the user should exist only on one machine.
- Attach the user's home-manager module only on the hosts where that user's environment should appear.

### Dotfiles And Shell Scripts

Do not manually copy dotfiles after installation. Manage them through home-manager.

Use one of two patterns.

### Pattern 1: Use Native Home-Manager Options

Current Git config already follows this pattern:

```nix
programs.git = {
  userName = "Geoffrey Thomas";
  userEmail = "you@example.com";
};
```

Use this pattern first when a good native option exists.

### Pattern 2: Keep A Literal File In The Repo

If you want to preserve an existing file mostly as-is, create a per-user files directory such as `users/thomasga/files/` and link it with `home.file`.

Example `.gitconfig`:

```nix
home.file.".gitconfig".source = ./files/gitconfig;
```

Example custom shell script:

```nix
home.file.".local/bin/dev-shell".source = ./files/dev-shell;
```

### Desktop Application Policy

This repo uses a layered application policy.

1. System modules own hardware support, services, and mandatory tools.
2. Desktop roles own the shared GNOME baseline and removal of unwanted GNOME applications.
3. User home-manager modules own optional desktop applications, dotfiles, and personal workflows.

Use this decision guide:

- If software affects machine operation, put it in NixOS.
- If software affects a person's workflow, put it in that user's home-manager config.
- If several users may want it, create a reusable opt-in user module.

### Remove GNOME Applications You Do Not Want

GNOME package pruning belongs in `roles/desktop/gnome.nix`, not in per-user config.

Examples of applications you may want to prune from the default desktop baseline include:

- Tour
- Help
- Games
- other default GNOME utilities you do not actually use

### Make GUI Apps Optional Per User

Do not install apps like VS Code, Firefox, or Chrome globally if you want them to appear only for users who choose them.

Preferred model:

1. Keep them out of the global desktop role.
2. Add them in the relevant user module.
3. If several users may want them, factor them into a reusable opt-in module.

Current concrete example: `users/thomasga/vscode.nix` enables VS Code through home-manager rather than the system profile.

Shared optional apps for a user can live in `users/common/`. For example, a module like `users/common/gui-apps.nix` is the right place for shared opt-in GUI packages such as Firefox, Fedora Media Writer, Bitwarden, and Chrome.

Current concrete ownership in this repo:

- `roles/desktop/gnome.nix` enables GNOME and dconf settings.
- `roles/common/flatpak.nix` enables Flatpak and Flatseal as optional platform services.
- `roles/common/gaming.nix` enables Steam as an optional gaming platform.
- `roles/common/base.nix` contains core system policy.
- `flake.nix` enables unfree packages needed by Chrome and Steam.
- `users/common/gui-apps.nix` enables Firefox and adds Fedora Media Writer, Bitwarden, Chrome, and Signal Desktop for any user that imports it.
- `users/thomasga/default.nix` opts `thomasga` into that shared GUI app set.
- `roles/common/users.nix` puts `thomasga` in `wheel`, which is why that user can administer the Framework laptop.

Example opt-in browser module:

```nix
{ pkgs, ... }:

{
  programs.firefox.enable = true;
  home.packages = [ pkgs.firefox ];
}
```

Chrome follows the same pattern, but `pkgs.google-chrome` also requires unfree package policy.

In this repo, that policy is set in `flake.nix`.

### User Theme, Background, And GNOME Preferences

Per-user GNOME appearance belongs under that user's home-manager config, not in the system desktop role.

- Put wallpaper files under `users/<name>/files/`.
- Link them into the home directory with `home.file` from a user module.
- Set dark mode, accent color, and wallpaper through `dconf.settings` in a user module such as `users/thomasga/gnome.nix`.

If the source wallpaper format is not one GNOME reliably consumes directly, keep the upstream source file in the repo and convert it during the Home Manager build.

For `thomasga`, the concrete setup is:

- Source asset: `users/thomasga/files/wallpapers/space-shuttle.jxl`
- Conversion and GNOME settings: `users/thomasga/gnome.nix`
- Resulting linked wallpaper: `~/Pictures/Wallpapers/space-shuttle.png`

`users/thomasga/gnome.nix` converts the checked-in Fedora `.jxl` source to `.png` with `pkgs.libjxl` and points both `picture-uri` and `picture-uri-dark` at the generated PNG. That avoids relying on runtime JPEG XL wallpaper support.

### Validation Commands

Before switching on a real machine, use a Linux or WSL environment with Nix
installed.

```bash
nix develop -c pre-commit run --all-files
nix flake check
nix eval .#nixosConfigurations.framework.config.age.identityPaths --json
nix build .#nixosConfigurations.framework.config.system.build.toplevel
```

Those commands work on non-NixOS hosts with Nix installed. `nixos-rebuild` itself only makes sense on NixOS or from a NixOS installer environment.

Then apply on the target NixOS system:

```bash
sudo nixos-rebuild dry-activate --flake .#framework
sudo nixos-rebuild switch --flake .#framework
```
