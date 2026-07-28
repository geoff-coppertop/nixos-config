# NixOS Config

This repo is the source of truth for machine setup, user setup, secrets wiring, and update policy. There are two main tasks it supports: provisioning a machine already defined here, and adding an entirely new machine to the repo.

## Contents

- [Repository Model](#repository-model)
- [Machine Naming](#machine-naming)
- [WSL Setup](#wsl-setup)
  - [Rebuilding an existing install](#rebuilding-an-existing-install)
- [Updating Machines](#updating-machines)
  - [Automatic updates](#automatic-updates)
  - [System updates (requires wheel)](#system-updates-requires-wheel)
  - [Monthly flake input update](#monthly-flake-input-update)
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
- [Provisioning defiant (Raspberry Pi 4)](#provisioning-defiant-raspberry-pi-4)
  - [Phase 0 — Preparation](#phase-0--preparation-on-enterprise-d-before-touching-the-pi)
  - [Phase 1 — First boot and Unifi setup](#phase-1--first-boot-and-unifi-setup)
  - [Phase 2 — First full deploy](#phase-2--first-full-deploy)
  - [Phase 3 — Service setup](#phase-3--service-setup)
- [Defining a New Machine](#defining-a-new-machine)
  - [Repository Structure](#repository-structure)
  - [Secrets and SSH Setup](#secrets-and-ssh-setup)
- [Reference](#reference)
  - [Secrets Management](#secrets-management)
  - [Wi-Fi Pre-configuration](#wi-fi-pre-configuration)
  - [Hibernation And Power](#hibernation-and-power)
  - [USB Debug Probes (udev)](#usb-debug-probes-udev)
  - [draw.io And Obsidian](#drawio-and-obsidian)
  - [Connect IQ SDK (Garmin)](#connect-iq-sdk-garmin)
  - [EasyEffects (Framework Speaker EQ)](#easyeffects-framework-speaker-eq)
  - [Change GNOME Or Kernel Policy Later](#change-gnome-or-kernel-policy-later)
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

When placing new configuration:

- If it affects machine operation, put it in the system layer: `hosts/<machine>/` for machine-specific behavior, `roles/` for shared system policy, or `modules/` for reusable NixOS features.
- If it affects a person's workflow, put it in that user's home-manager config under `users/<name>/`, in a profile such as `users/<name>/desktop.nix` (full GUI) or `users/<name>/headless.nix` (CLI-only).
- If several users may want it, create a reusable opt-in user module under `users/common/` and import it from the relevant profile instead of forcing it globally.

## Machine Naming

Machine names are drawn from ships, stations, and notable locations in Star Trek, Star Wars, and Battlestar Galactica:

- Prefer single-word names; use multiple words only when the canonical name genuinely requires it
- Hyphenate multi-word names (e.g., `enterprise-d` because the D is part of the official ship designation NCC-1701-D)
- No character names
- Physical machines: named after specific vessels or stations (e.g., `enterprise-d`, `galactica`, `defiant`)
- WSL instances: `holodeck-<NN>` (e.g., `holodeck-01`, `holodeck-02`)

The machines in this repo are:

| Machine | Type | Host entrypoint |
| --- | --- | --- |
| `enterprise-d` | Framework laptop (physical, x86\_64) | `hosts/enterprise-d/configuration.nix` |
| `holodeck-01` | NixOS WSL on Windows (x86\_64) | `hosts/holodeck-01/configuration.nix` |
| `defiant` | Raspberry Pi 4 homelab server (aarch64) | `hosts/defiant/configuration.nix` |

- Flake entry: `flake.nix`

## WSL Setup

**Prerequisite:** WSL2 must be enabled on Windows. If it isn't, open an elevated PowerShell and run `wsl --install`, then reboot once.

**Fresh WSL bootstrap is not currently available.** `install.py`'s WSL flow (fetch NixOS-WSL, `wsl --import`, apply the flake) was pulled out of the Python tooling rewrite pending real validation — it had never actually been run end to end, unlike the disko flow, which was tested thoroughly. It'll return in a follow-up once there's an environment to validate it against, or may not return at all if WSL usage here winds down as expected. If you need to bootstrap a **new** WSL machine before that lands, ask first rather than reaching for old instructions — nothing in this repo currently automates it.

`holodeck-01` already exists and boots normally; none of the above affects rebuilding it.

### Rebuilding an existing install

If holodeck-01 is already running with the age identity installed, rebuild in place from inside WSL:

```bash
sudo nixos-rebuild switch --flake github:geoff-coppertop/nixos-config#holodeck-01
```

Or pull the repo locally and use a local flake path:

```bash
sudo nixos-rebuild switch --flake /path/to/nixos-config#holodeck-01
```

## Updating Machines

### Automatic updates

`roles/common/base.nix` enables `system.autoUpgrade` for every host: it fetches `github:geoff-coppertop/nixos-config#<hostname>` weekly and stages the result as the next boot entry (`operation = boot`, `allowReboot = false`). Nothing reboots automatically; apply the staged generation at your convenience. Because it tracks the GitHub remote, only pushed commits are picked up.

On hosts with `custom.isLaptop = true` (currently `enterprise-d`), the upgrade additionally skips while on battery — the same `ConditionACPower` gating used for NAS backups.

Two more opt-in modules add update mechanisms for specific hosts:

| Module | Option | Host(s) enabled | What it does |
| --- | --- | --- | --- |
| `modules/flatpak.nix` | `custom.flatpak.enable` | `enterprise-d` | Weekly Flatpak update timer (also AC-gated on laptops), plus update-on-activation |
| `modules/fwupd.nix` | `custom.fwupd.enable` | `enterprise-d` | Enables the fwupd daemon for LVFS firmware updates; apply with `fwupdmgr refresh && fwupdmgr update` |

### System updates (requires wheel)

| Machine | Update command | Where to run |
| --- | --- | --- |
| `enterprise-d` | `sudo nixos-rebuild switch --flake .#enterprise-d` | On `enterprise-d` |
| `holodeck-01` | `sudo nixos-rebuild switch --flake .#holodeck-01` | Inside the WSL distro |
| `defiant` | `nixos-rebuild switch --flake .#defiant --target-host thomasga@defiant --use-remote-sudo` | From any machine with SSH + Nix |
| `enterprise-d` (remote) | `nixos-rebuild switch --target-host thomasga@enterprise-d --flake .#enterprise-d` | From any machine with SSH + Nix |

### Monthly flake input update

```bash
nix flake update
sudo nixos-rebuild dry-activate --flake .#enterprise-d
sudo nixos-rebuild switch --flake .#enterprise-d
```

### User environment updates (self-serve, no sudo)

Each user can update their own home-manager environment without a full system rebuild and
without `sudo`. The flake exposes a `homeConfigurations.<user>@<machine>` output for every
user–machine pair.

```bash
# Apply your home-manager config on the current machine
home-manager switch --flake .#thomasga@enterprise-d

# Or from a branch / local checkout without switching the system
git checkout my-dotfiles-branch
home-manager switch --flake .#thomasga@enterprise-d
```

This works for any user, including users who are not in the `wheel` group. Only changes
that affect the system layer (new packages in `environment.systemPackages`, firewall rules,
new user accounts, etc.) require a wheel-gated `nixos-rebuild switch`.

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
cd /home/thomasga/builds/geoff-coppertop/nixos-config
nix --version                          # should be 2.18+
id -Gn | grep nix-users                # multi-user only
nix flake metadata path:$PWD           # verify flake resolution
nix develop -c bash -lc 'command -v age agenix pre-commit alejandra statix deadnix markdownlint'
```

All commands should succeed. The final one verifies the dev shell includes `age`, `agenix`, and all lint tools.

### Dev Shell And Repo Tools

Enter the development shell:

```bash
cd /home/thomasga/builds/geoff-coppertop/nixos-config
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

This is the standard workflow to install a machine already defined in this repo (such as `enterprise-d`). The repo handles all configuration; you provide the physical machine and initial boot media.

### Create a NixOS Installer USB

Run these steps from your Linux or WSL shell after verifying setup above.

1. Enter the repo shell:

   ```bash
   cd /home/thomasga/builds/geoff-coppertop/nixos-config
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
   age-keygen -o ~/.config/agenix/enterprise-d.age
   chmod 600 ~/.config/agenix/enterprise-d.age
   ```

4. Copy the public keys printed by `age-keygen` into `secrets/secrets.nix`.

   - Set `offlineAdmin` to the offline recovery key.
   - Set `enterprise-d` to the host key for `enterprise-d`.

   The checked-in secret recipients are intentionally enterprise-d-scoped. Do not add a new host as a recipient unless that host actually needs that secret.

5. Store the offline admin private key or its recovery material in Bitwarden. Do not install that key onto machines.

6. Before the first `nixos-install`, copy the host private key into the mounted target so the installed system can decrypt secrets on first boot. The installer script handles this interactively, or run it manually:

   ```bash
   sudo python3 tools/install_age_identity.py --file ~/.config/agenix/enterprise-d.age
   ```

   Pass `--shred` to erase the source file after copying.

7. On an already-installed machine, install or rotate the dedicated host identity in place with:

   ```bash
   sudo python3 tools/install_age_identity.py --file ~/.config/agenix/enterprise-d.age \
     --target /var/lib/agenix/identity
   ```

#### Creating Or Rotating Secrets

Never create plaintext files under `secrets/`. Use the helper command so the plaintext only exists in a temporary editor buffer.

For a brand-new secret:

1. Add a recipient entry to `secrets/secrets.nix`. Example:

   ```nix
   "thomasga/nas-smb-credentials.age".publicKeys = [enterprise-d offlineAdmin];
   ```

2. Create or edit the encrypted file:

   ```bash
   EDITOR=nano nix run .#secret-edit -- secrets/thomasga/nas-smb-credentials.age
   ```

3. If NixOS or home-manager needs a runtime path for that secret, expose it through `age.secrets` in the host's `secrets.nix` (e.g. `hosts/enterprise-d/secrets.nix`).

   To rotate an existing secret:

   ```bash
   EDITOR=nano nix run .#secret-edit -- secrets/thomasga/restic-password.age
   ```

   After changing recipients in `secrets/secrets.nix`, re-encrypt every tracked secret with the offline admin key available locally:

   ```bash
   # The offline admin age private key must be present at ~/.config/agenix/admin.age
   # on the machine running this command. Retrieve it from Bitwarden first if needed:
   mkdir -p ~/.config/agenix && chmod 700 ~/.config/agenix
   # paste key material into ~/.config/agenix/admin.age, then:
   chmod 600 ~/.config/agenix/admin.age
   nix run .#secret-rekey
   shred -u ~/.config/agenix/admin.age
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

Use `tools/enroll.py` to generate a per-machine SSH keypair, encrypt it as an agenix secret, and wire everything up automatically:

```bash
nix develop -c python3 tools/enroll.py <machine-name>
```

The script:

1. Adds the machine's age identity to `secrets/secrets.nix` (generated or provided)
2. Generates an ed25519 SSH keypair, encrypts the private key with `age`, and shreds the plaintext
3. Creates `hosts/<machine>/secrets.nix` and adds its import to `configuration.nix`
4. Adds the machine with its `userPublicKey` to `lib/ssh-hosts.nix`
5. Re-keys all secrets so the machine is a recipient

The private key is decrypted at runtime by agenix and deployed by home-manager. The public key in `lib/ssh-hosts.nix` is automatically added to `openssh.authorizedKeys.keys` on every enrolled machine — no manual `authorized_keys` editing needed.

For machines already provisioned (e.g., `enterprise-d`), the `thomasga/ssh-id-ed25519-enterprise-d.age` secret already exists. Run the enrollment script and skip the SSH key generation step if you only need to add a new machine's identity.

### Collect Host SSH Public Key After Deploy

The deployed machine generates its own SSH host keypair automatically when sshd starts. This is separate from the login keypair above and is what remote machines use to verify they are talking to the correct host.

When enterprise-d boots with sshd enabled in [hosts/enterprise-d/configuration.nix](hosts/enterprise-d/configuration.nix), NixOS automatically generates the host keypair in `/etc/ssh/ssh_host_ed25519_key` and `/etc/ssh/ssh_host_ed25519_key.pub`. The private key stays on the machine unencrypted (standard SSH practice); only the public key is needed in the repo.

After enterprise-d boots for the first time:

1. Collect the host's SSH public key from the running machine:

   ```bash
   ssh-keyscan -t ed25519 enterprise-d 2>/dev/null
   ```

   This will print a line like:

   ```bash
   enterprise-d ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDCRCqI2...
   ```

2. Verify the fingerprint out-of-band (log in to the machine and compare `ssh-keygen -l -f /etc/ssh/ssh_host_ed25519_key.pub` to what ssh-keyscan printed).
3. Extract just the public key portion and add it to `lib/ssh-hosts.nix` in the `publicKey` field for that machine.

#### Pin Managed Host Keys

`lib/ssh-hosts.nix` is the single inventory for all managed machines. Each entry has:

- `hostName`: the real SSH hostname
- `aliases`: optional short names you want in SSH config
- `publicKey`: the verified SSH **host** public key (server identity; `null` until pinned)
- `user`: the default SSH username
- `userPublicKey`: the user's SSH **login** public key (login access; `null` until enrolled)

`modules/ssh-known-hosts.nix` turns non-null `publicKey` values into `programs.ssh.knownHosts` so clients don't prompt on first connect. `roles/common/users.nix` aggregates non-null `userPublicKey` values into `openssh.authorizedKeys.keys` so every enrolled machine accepts logins from every other enrolled machine automatically.

`tools/enroll.py` populates `userPublicKey` as part of enrollment. To pin `publicKey` after first boot, collect the host key and paste it in:

```bash
ssh-keyscan -t ed25519 <machine> 2>/dev/null
# paste the key portion into lib/ssh-hosts.nix as publicKey = "ssh-ed25519 AAAA..."
```

Verify the fingerprint out-of-band before committing. `ssh-keyscan` is a collection mechanism, not a trust oracle.

### Backups

`modules/backups.nix` provides client-pushed restic backups to a NAS share. The NAS is mounted on demand over SMB or NFS. Backups run on a daily timer. On hosts marked as laptops, backups only run when AC power is connected. If the NAS is unreachable, the job exits cleanly.

#### How It Works

Each enabled user gets a separate systemd service (`nas-backup-<user>`) and timer (`nas-backup-<user>-timer`). The service:

1. Triggers an automount of the NAS share.
2. Exits silently if the share is not reachable.
3. Initialises a restic repository on first run.
4. Backs up the configured paths (default: `/home/<user>`, excluding `.cache`).
5. Prunes old snapshots according to the retention policy (7 daily, 4 weekly, 12 monthly, 3 yearly by default). This progressively reduces granularity over time while keeping long-term coverage.

#### Enabling Backups on a Host

**1. Create the encrypted SMB credentials secret for each user.**

If the secret file is new, add a recipient entry first:

```nix
"thomasga/nas-smb-credentials.age".publicKeys = [enterprise-d offlineAdmin];
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

And expose it at a known path in the host's `secrets.nix`:

```nix
age.secrets."thomasga/nas-smb-credentials".file =
  ../../secrets/thomasga/nas-smb-credentials.age;
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

#### Checking Backup Status

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

#### Adding a New Host

1. Import `../../modules/backups.nix` in the host's `configuration.nix`.
2. Set `custom.isLaptop` appropriately.
3. Set `custom.backups.nas.host`, `nas.share`, `nas.credentialsFile`, and enable at least one user.
4. Ensure the per-user restic password and SMB credentials secrets are declared.

#### Limitations

- Backups target `/home/<user>` by default. For service state outside `/home`, override `paths` explicitly. Example from `defiant` backing up Home Assistant:

  ```nix
  custom.backups.users = {
    hass = {
      enable = true;
      paths = ["/var/lib/hass"];
      excludePatterns = ["/var/lib/hass/.storage/lovelace*"];
    };
  };
  ```

  `passwordFile` defaults to `/run/agenix/<name>/restic-password` — override it explicitly
  only if the secret doesn't follow that convention.

- Snapper manages local btrfs snapshots for rollback; it is not involved in NAS backups.
- If SMB is unavailable at boot, the automount fails silently and the next timer invocation will retry.

### Boot the Machine From USB

1. Insert the USB stick.
2. Power on the machine and open the boot menu.
3. Boot the NixOS installer USB in UEFI mode.
4. Leave Secure Boot off for the first install. Secure Boot is enabled later through lanzaboote after the system is installed.

**Do not use the graphical installer.** When the desktop appears, just open a terminal — the script in step 4 handles the full install.

### Run the Installer Script From the Live Session

Once booted into the NixOS installer, open a terminal and run the installer. Have ready:

- The target disk device name (run `lsblk` to identify it, e.g. `/dev/nvme0n1`)
- The LUKS passphrase you want to use for disk encryption
- A second USB drive with the machine's age identity file (optional — see "Defining a New Machine"; you can add the key after install if needed)

The stock installer ISO ships with flakes disabled, so fetch and run the installer through `nix-shell` (the classic, non-flake Nix CLI, which needs no extra flags on a stock ISO) rather than `nix run`. `install.py` clones the full repo to `/tmp/nixos-config` and re-execs itself from there automatically if it doesn't find its sibling modules alongside it — so this is the entire command, no separate clone step needed:

```bash
nix-shell -p python3 git --run \
  'python3 <(curl -fsSL https://raw.githubusercontent.com/geoff-coppertop/nixos-config/master/tools/install.py)'
```

The tool will prompt for a machine to install from the menu, then automatically:

1. Clone the repo to `/tmp/nixos-config` and re-run itself from there
2. Enroll the machine if it isn't already (generate its age identity and SSH host key) — prompts inline
3. List disks and prompt for the target device and LUKS passphrase
4. Prompt for an age identity key source (USB drive, file path, or skip — add it after install if needed)
5. Secure the live `nixos` session
6. Run disko to partition, format, and mount the disk
7. Copy the repo into `/mnt/etc/nixos/nixos-config`
8. Install the age identity key, if provided
9. Generate Secure Boot keys under `/mnt/etc/secureboot`
10. Run `nixos-install`

**WARNING:** disko will destroy all data on the target disk.

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

After the system boots:

1. **Enroll TPM2 for LUKS auto-unlock** (see [TPM Auto-Unlock After Install](#tpm-auto-unlock-after-install))
2. **Collect the SSH host public key** and add it to `lib/ssh-hosts.nix` (see [Collect Host SSH Public Key After Deploy](#collect-host-ssh-public-key-after-deploy))
3. **Generate and install your SSH login credentials** (see [Generate SSH Login Credentials](#generate-ssh-login-credentials))
4. **Test hibernation** (see [Hibernation And Power](#hibernation-and-power))
5. **Validate the system** (see [Validation Commands](#validation-commands))

## Provisioning defiant (Raspberry Pi 4)

defiant is a headless aarch64 homelab server running Traefik, Home Assistant, the Matter server, AdGuard Home, Zigbee2MQTT, Z-Wave JS, and ADS-B.

### Phase 0 — Preparation (on enterprise-d, before touching the Pi)

**Retrieve the offline admin age key** (required for rekeying secrets):

The offline admin age private key lives only in Bitwarden — it is never installed on any machine
permanently. Before creating or rekeying secrets, place it on enterprise-d temporarily:

```bash
mkdir -p ~/.config/agenix && chmod 700 ~/.config/agenix
# Paste the private key from Bitwarden into:
nano ~/.config/agenix/admin.age
chmod 600 ~/.config/agenix/admin.age
```

Remove it again after rekeying is complete (`shred -u ~/.config/agenix/admin.age`).

**Enroll the machine:**

```bash
nix develop -c python3 tools/enroll.py defiant
# Choose: 2) Generate a new keypair here
```

**Create service secrets** (one by one, storing passphrases in Bitwarden):

```bash
EDITOR=nano nix run .#secret-edit -- secrets/defiant/cloudflare-api-token.age
# Contents: CF_DNS_API_TOKEN=<Cloudflare Zone:DNS:Edit token for coppertop.ca>

EDITOR=nano nix run .#secret-edit -- secrets/defiant/nas-smb-credentials.age
# Contents: username=<nas-user>\npassword=<nas-password>

# One restic-password secret per backup job — each is keyed to the entry
# name under custom.backups.users, not the machine (each entry gets its
# own restic repo). Same passphrase or distinct, your call.
EDITOR=nano nix run .#secret-edit -- secrets/hass/restic-password.age
EDITOR=nano nix run .#secret-edit -- secrets/zigbee2mqtt/restic-password.age
EDITOR=nano nix run .#secret-edit -- secrets/zwave-js/restic-password.age
EDITOR=nano nix run .#secret-edit -- secrets/adguardhome/restic-password.age
# Contents (each): single passphrase line
```

**Generate Zigbee and Z-Wave security keys before first deploy.** Both
services require real keys to be present from their very first start —
neither auto-generates a working one on its own, and regenerating either
after devices are paired/included breaks every one of them, requiring a
full re-pair. Generate once here, before the SD card is even flashed:

```bash
python3 -c "import secrets; print('[' + ','.join(str(b) for b in secrets.token_bytes(16)) + ']')"
EDITOR=nano nix run .#secret-edit -- secrets/defiant/zigbee-network-key.age
# Contents: paste the bracketed byte array verbatim, e.g. [12,34,...,255]

for name in S0_Legacy S2_Unauthenticated S2_Authenticated S2_AccessControl; do
  echo "$name=$(openssl rand -hex 16)"
done
EDITOR=nano nix run .#secret-edit -- secrets/defiant/zwave-secrets.age
# Contents (JSON, one securityKeys object with all four printed above):
# {
#   "securityKeys": {
#     "S0_Legacy": "<hex>",
#     "S2_Unauthenticated": "<hex>",
#     "S2_Authenticated": "<hex>",
#     "S2_AccessControl": "<hex>"
#   }
# }
```

**Rekey and clean up:**

```bash
nix run .#secret-rekey
shred -u ~/.config/agenix/admin.age
nix develop -c pre-commit run --all-files
git add -p && git commit -m "feat: enroll defiant and add service secrets"
git push
```

**Build and flash the SD card:**

```bash
nix run .#install
# Select: defiant
```

Cross-compiles the SD image (several minutes), decompresses it, prompts for and
confirms the target device before flashing, then installs `defiant`'s age
identity (`~/.config/agenix/defiant.age`, generated during enrollment above)
onto the image so it can decrypt its secrets at first boot. Unmounts and
powers off the device automatically when it's done — safe to remove as soon
as the tool exits, no manual eject needed.

### Phase 1 — First boot and Unifi setup

1. Connect ethernet, insert SD card, power on. Wait ~2 minutes.
2. In Unifi console → Clients, find defiant by hostname or MAC. Note the IP.
3. Set a DHCP reservation for defiant's MAC address (fixed LAN IP).
4. Set defiant's reserved IP as DNS Server 1 in the LAN DHCP settings.
5. Collect the SSH host key and pin it:

   ```bash
   ssh-keyscan -t ed25519 <defiant-ip> 2>/dev/null
   # Verify fingerprint: ssh thomasga@<defiant-ip> "ssh-keygen -l -f /etc/ssh/ssh_host_ed25519_key.pub"
   # Paste verified key into lib/ssh-hosts.nix as publicKey = "ssh-ed25519 AAAA..."
   ```

6. Update the `lanIp` placeholder in `hosts/defiant/configuration.nix` with the reserved IP. Commit and push.

### Phase 2 — First full deploy

```bash
nixos-rebuild switch --flake .#defiant \
  --target-host thomasga@defiant \
  --use-remote-sudo
```

Zigbee2MQTT and Z-Wave JS start up using the keys created in Phase 0 — no
further extraction step needed.

### Phase 3 — Service setup

| Service | URL | Action |
| --- | --- | --- |
| AdGuard Home | `https://dns.coppertop.ca` | Complete setup wizard; upstream DNS: `127.0.0.1:5335` |
| Home Assistant | `https://home.coppertop.ca` | Restore backup or complete onboarding |
| Zigbee2MQTT | `https://zigbee.coppertop.ca` | Enable join mode; pair devices (see notes below) |
| Z-Wave JS | HA → Integrations | Connect to `ws://localhost:3001`; include Z-Wave devices |
| Bambu Lab | HA → Integrations | Add integration; choose LAN mode (disables Handy app) or cloud mode |

**IKEA device pairing notes:**

- **Somrig button** — pair normally; automations should use `initial_press` only (`long_press`/`double_press` unreliable); re-pair after any OTA update.
- **VALLHORN/PARASOLL** — if the interview fails, retry pairing. Do not set occupancy timeout below 90 s on any IKEA motion sensor.
- **E1745 motion sensor** — do **not** apply OTA firmware; it disables motion detection.
- **STARKVIND air purifier** — no known issues; pair normally.

### DNS bypass

Clients needing unfiltered DNS (skips AdGuard ad-blocking, retains `coppertop.ca` resolution):

```bash
dig @defiant -p 5335 home.coppertop.ca
```

Point a device at `<defiant-ip>:5335` in its DNS settings to bypass AdGuard permanently.

## Defining a New Machine

To add an entirely new machine to this repo:

### Repository Structure

1. Create `hosts/<machine-name>/`.
2. Add `hosts/<machine-name>/configuration.nix` (imports hardware, power, disko).
3. Add `hosts/<machine-name>/hardware.nix` (hardware-scan output).
4. Add `hosts/<machine-name>/power.nix` (power and hibernate policy).
5. Add `hosts/<machine-name>/disko.nix` (disk layout if provisioning from this repo).
6. Register the machine in `flake.nix` under `nixosConfigurations` using `mkNixosSystem`:

```nix
nixosConfigurations."<machine-name>" = mkNixosSystem {
  system = "x86_64-linux";  # or "aarch64-linux" for ARM machines
  extraModules = [
    ./hosts/<machine-name>
    # add machine-specific modules as needed:
    # disko.nixosModules.disko            (physical machines with declarative disk layout)
    # lanzaboote.nixosModules.lanzaboote  (Secure Boot)
    # nixos-wsl.nixosModules.default      (WSL machines)
  ];
};
```

`mkNixosSystem` is defined in `lib/nixos-system.nix` and wires in `home-manager`, `agenix`, `allowUnfree`, and shared settings automatically.

### Secrets and SSH Setup

Run the enrollment script to generate the age identity, SSH keypair, and all config wiring in one step:

```bash
nix develop -c python3 tools/enroll.py <machine-name>
```

See [Generate SSH Login Credentials](#generate-ssh-login-credentials) for a full description of what the script does and the options it presents.

Then:

1. **Follow the provisioning workflow** to install the machine.
2. **Collect the SSH host public key** after first boot and pin it in `lib/ssh-hosts.nix`.

## Reference

### Secrets Management

This repo uses agenix for committed secrets and Bitwarden for recovery material. Secrets live in `secrets/` and are safe to commit; only the decrypted content is sensitive.

Runtime decryption on NixOS uses the dedicated age private key at `/var/lib/agenix/identity` (configured in `modules/secrets.nix`). Each host's `secrets.nix` (e.g. `hosts/enterprise-d/secrets.nix`) declares the `age.secrets` for that machine.

#### First-Time Secret Bootstrap

This repo encrypts the root filesystem with LUKS and seals it to the TPM 2.0 chip in enterprise-d.

#### Encryption At Install Time

The disko configuration creates an encrypted root partition. During provisioning (step 4 above), you provide a LUKS passphrase in `/tmp/encryption-password`. This passphrase will unlock the root filesystem if the TPM is unavailable or tampered with.

**Important:** Write down or save this passphrase in a secure location outside the machine. You will need it if:

- The TPM is reset or replaced
- The firmware is updated and TPM state is cleared
- You boot from a rescue USB and need to manually unlock the disk

#### TPM Auto-Unlock After Install

After the system boots and you are logged in, enroll the LUKS key into the TPM:

```bash
sudo systemd-cryptenroll /dev/disk/by-partlabel/root --tpm2-device=auto --tpm2-pcrs=0,1,3,7
```

The `--tpm2-pcrs` argument seals the key to specific firmware/bootloader measurements:

- `0`: firmware configuration
- `1`: bootloader configuration
- `3`: bootloader state
- `7`: Secure Boot state

After enrollment, reboot. The system should now unlock automatically at boot without a passphrase prompt.

#### Verify TPM Enrollment

To check that TPM enrollment is active:

```bash
sudo systemd-cryptenroll /dev/disk/by-partlabel/root --json | jq '.[] | select(.type=="tpm2")'
```

A non-empty result confirms TPM2 enrollment is active.

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
   "wifi/newnet.age".publicKeys = [enterprise-d offlineAdmin];
   ```

2. **`roles/common/networking.nix`** — expose the secret at runtime (alongside the existing WiFi entries):

   ```nix
   "wifi/newnet".file = ../../secrets/wifi/newnet.age;
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

After `sudo nixos-rebuild switch --flake .#enterprise-d`:

```bash
nmcli connection show              # profiles should appear
sudo cat /etc/NetworkManager/system-connections/agt-home.nmconnection
```

### Hibernation And Power

This repo is set up to hibernate through the dedicated swap partition.

- Resume device: `/dev/disk/by-partlabel/swap`
- Root subvolume: `subvol=@`
- Home subvolume: `subvol=@home`
- AMD CPU policy: `amd_pstate=active`

After installation, validate hibernation with:

```bash
systemctl hibernate
```

Then verify the machine resumes correctly.

### USB Debug Probes (udev)

`custom.debugProbes.enable` (`modules/debug-probes.nix`) installs udev rules
for common USB JTAG/SWD debug probes — ST-Link, J-Link, FTDI-based adapters,
and CMSIS-DAP compatible devices (which includes the Raspberry Pi Debug
Probe). The rules themselves live in
`modules/udev-rules/69-probe-rs.rules`, a verbatim copy of the
[probe-rs](https://probe.rs/)/OpenOCD project's udev rules (same file also
kept in the `helicopter-collective` repo's `.devcontainer/`), and are loaded
via `services.udev.packages` — **not** `services.udev.extraRules`. The
module also creates the `plugdev` group (the rules' `GROUP="plugdev"`
fallback) and `thomasga` is a member of it via
`hosts/enterprise-d/configuration.nix`.

**Why `services.udev.packages` and not `extraRules`:** this file's own name
matters. It's called `69-probe-rs.rules` upstream specifically so it sorts
*before* systemd's own `70-uaccess.rules`/`73-seat-late.rules` — those files
only queue the `uaccess` ACL-granting builtin if a device is already
`TAG=="uaccess"` at the point they're evaluated, and udev processes all rule
files in one linear pass sorted by filename. `services.udev.extraRules`
merges its content into a single generated file always named
`99-local.rules`, which sorts *after* 73 — silently breaking the ACL grant
on every first-ever enumeration of a device, since our `TAG+="uaccess"`
assignment would run too late to be seen. `services.udev.packages` preserves
each file's own name in `/etc/udev/rules.d/`, restoring the intended
ordering. (This bug is easy to miss because re-triggering an
already-enumerated device "fixes" it — the tag persists in that device's
udev database entry from an earlier pass — making it look like an
intermittent timing race rather than a deterministic ordering bug.)

This is necessary because embedded-dev devcontainers (e.g.
`helicopter-collective`) don't create their own USB device nodes — they
bind-mount the host's `/dev/bus/usb` into the container
(`devcontainer.json`'s `mounts`) and rely on `--userns=keep-id` to map the
container user to the host user's UID. Permission checks on that bind mount
are enforced by the kernel against the same device node the host owns, so
whatever the *host's* udev grants `thomasga` (via `plugdev` group membership
and the rules' `TAG+="uaccess"` ACL) is exactly what the container process
gets — there's no way to grant this access from inside the container image.
The udev rules must live here, on the NixOS host, not in the devcontainer.

With the ordering fixed, a fresh `nixos-rebuild switch` plus a normal
plug-in of the probe is enough — no manual `udevadm trigger` or replug
workaround needed.

### draw.io And Obsidian

`users/thomasga/drawio.nix` installs `pkgs.drawio` (the standalone draw.io
desktop app) alongside Obsidian, and registers `*.drawio`/`*.dio` as a
shared-mime-info type (`application/vnd.jgraph.mxfile`) so file managers and
"Open With" dialogs default those extensions to draw.io instead of treating
them as plain XML.

Editing `.drawio` diagrams *inside* Obsidian notes requires the community
plugin "draw.io" (id `drawio`, by somesanity —
[somesanity/draw-io-obsidian](https://github.com/somesanity/draw-io-obsidian),
listed at
[community.obsidian.md/plugins/drawio](https://community.obsidian.md/plugins/drawio)).
It runs a bundled local Express server to edit diagrams fully offline. Its
build artifacts are only published as GitHub release assets, not committed
to the repo, so it isn't vendored declaratively here. Install it once per
vault via Obsidian's UI: **Settings → Community plugins → Browse**, search
"draw.io", install, and enable. Obsidian owns
`.obsidian/community-plugins.json` from then on (it rewrites the file live
as plugins are toggled), so this repo intentionally doesn't manage that file
— doing so would clobber plugin state on every `nixos-rebuild switch`.

### Connect IQ SDK (Garmin)

`roles/dev/tools.nix` installs `connect-iq-sdk-manager` (a non-interactive
Go CLI replacement for Garmin's broken Electron/webkit2gtk SDK Manager GUI —
[lindell/connect-iq-sdk-manager-cli](https://github.com/lindell/connect-iq-sdk-manager-cli))
and a JDK, since the SDK's `monkeyc` compiler is a Java app.

Two things are automated so a fresh machine needs no interactive setup:

- `users/thomasga/connect-iq.nix` creates `~/.Garmin/ConnectIQ/Sdks` and
  accepts Garmin's SDK license agreement on first home-manager activation.
- `users/thomasga/shell.nix` adds the currently selected SDK's `bin/` to
  `PATH` on fish startup, so `monkeyc` is on `PATH` without a manual export
  and stays correct across `sdk set <version>` switches.
- `modules/bin-compat.nix` (`custom.binCompat.enable`) symlinks `/bin/bash`,
  since `monkeyc`'s shebang expects it and NixOS doesn't provide it by
  default.

Manage SDK versions and devices with:

```bash
connect-iq-sdk-manager sdk list
connect-iq-sdk-manager sdk download <version>
connect-iq-sdk-manager sdk set <version>
connect-iq-sdk-manager device download
```

### EasyEffects (Framework Speaker EQ)

`users/thomasga/easyeffects.nix` enables `services.easyeffects` (home-manager)
as a per-user systemd service, sitting on top of pipewire
(`roles/desktop/audio.nix`) to globally EQ the Framework 13's thin,
down-firing speakers. It relies on `programs.dconf.enable = true`, already
set system-wide by `roles/desktop/gnome.nix`.

Four community presets from
[ceiphr/ee-framework-presets](https://github.com/ceiphr/ee-framework-presets)
(`gracefu`, `kieran_levin`, `lappy_mctopface`, `philonmetal`) are fetched with
`pkgs.fetchurl`, pinned to a commit and content-hashed, and written straight
to `xdg.dataFile."easyeffects/output/<name>.json"` — matching the pattern
used elsewhere in this repo for third-party sources (`pkgs/search-light.nix`,
`pkgs/framework-control.nix`) rather than vendoring a copy of someone else's
files into git. To pick up an upstream preset change, bump the `rev` and the
corresponding `hash` in `users/thomasga/easyeffects.nix` together.
`lappy_mctopface` (tuned for on-lap use) loads at login via
`services.easyeffects.preset`; `kieran_levin` (flat, tuned for on-a-table
use) is the recommended alternative. Switch between them anytime from the
EasyEffects UI's preset dropdown — the daemon reloads without a rebuild. The
repo's "louder" preset variants were intentionally left out: upstream notes
they can introduce ~1ms audio artifacts on pause/play.

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

`wheel` is the admin group here, so this is the file to change if `thomasga` should be able to administer enterprise-d.

Home-manager attachment lives in `hosts/<machine>/default.nix`:

```nix
home-manager.users.thomasga = {
  imports = [../../users/thomasga/desktop.nix];
  custom.ssh.identitySecret = "ssh-id-ed25519-enterprise-d";
};
```

### Add A New User

Users are added in two phases: a one-time system bootstrapping step (requires wheel) and
ongoing self-serve home-manager updates (no sudo).

Not all users exist on all machines. Each machine declares exactly which users it has.

#### Phase 1 — System bootstrap (done once by a wheel user)

**1. Create the user's home-manager profile(s):**

```bash
# For a desktop machine:
users/alice/desktop.nix   # imports ../common/base.nix, ../common/cli, etc.

# For headless/WSL:
users/alice/headless.nix
```

**2. Create per-machine home modules** — one file per machine the user will have an account on:

```bash
# hosts/<machine>/home/alice.nix
{
  imports = [../../../users/alice/desktop.nix];   # or headless.nix
  custom.ssh.identitySecret = "ssh-id-ed25519-alice-<machine>";
}
```

**3. Declare the system account** in the relevant host config (groups are machine-specific):

```nix
# hosts/<machine>/configuration.nix
users.users.alice = {
  isNormalUser = true;
  extraGroups = ["networkmanager"];  # wheel only if admin
  hashedPassword = "...";
  shell = pkgs.fish;
};
```

**4. Attach home-manager** in `hosts/<machine>/default.nix`:

```nix
home-manager.users.alice.imports = [./home/alice.nix];
```

**5. Add `homeConfigurations` entries** in `flake.nix` for each machine:

```nix
"alice@enterprise-d" = mkHomeConfig {
  user = "alice";
  machine = "enterprise-d";
  hostSystem = "x86_64-linux";
};
```

**6. Add an SSH identity secret** (see Secrets section) and enroll it in `hosts/<machine>/secrets.nix`.

**7. Apply:**

```bash
nix develop -c pre-commit run --all-files
sudo nixos-rebuild switch --flake .#<machine>
```

This is the only step that requires `sudo`. After it completes, Alice's account exists and she
can self-serve from here on.

#### Phase 2 — Self-serve updates (Alice, no sudo)

Once the account exists, Alice updates her own environment at will:

```bash
git pull   # or check out any branch
home-manager switch --flake .#alice@enterprise-d
```

She can iterate on dotfiles, shell config, packages — anything in `users/alice/` — without
involving a wheel user or rebuilding the system.

### Assign A User To One Host Or All Hosts

- Declare the system account in a host-specific config if the user should only exist on that machine.
- Add a `hosts/<machine>/home/<user>.nix` and a `homeConfigurations` entry for each machine separately.
- Do not add a user to machines they don't use — groups, secrets, and home-manager builds are all per-machine.

### Dotfiles And Shell Scripts

Do not manually copy dotfiles after installation. Manage them through home-manager and the shared `dotfiles` repo.

There are now three patterns, in order of preference.

#### Pattern 1: Shared "Look And Feel" Via `dotfiles`

Fish aliases/functions and git aliases/commit-template are no longer rendered by home-manager. They live once in
[`geoff-coppertop/dotfiles`](https://github.com/geoff-coppertop/dotfiles), a plain-file repo also consumed by
`devcontainer-features`' `shell-baseline` feature, so the same shell/git behavior shows up on this machine and in
devcontainers without being hand-copied in three places.

- `dotfiles` is pinned as a non-flake input (`inputs.dotfiles = { url = "github:geoff-coppertop/dotfiles"; flake = false; };`)
  in `flake.nix`, the same way every other input is pinned via `flake.lock`.
- `users/common/cli/dotfiles.nix` links `${dotfiles}/fish/config.fish`, `${dotfiles}/git/config`, and
  `${dotfiles}/git/commit-template` straight into place with plain `home.file.<path>.source` — no extra package, no
  activation step. home-manager's own collision detection hard-errors at eval time if anything else tries to write
  those same paths.
- Because `programs.fish` stays disabled and `programs.git`/`programs.fzf`/`programs.starship`/`programs.zoxide` must
  not also write `~/.config/fish/config.fish` or `~/.config/git/config`, `fzf.nix`/`starship.nix`/`zoxide.nix` set
  `enableFishIntegration = false` (the init lines already live in `dotfiles`' `config.fish`), `git.nix` drops
  `programs.git.enable` entirely (installing the `git` binary via `home.packages` instead), and
  `users/thomasga/git.nix` no longer sets `alias`/`color`/`commit.template`/etc. through `programs.git.settings`.
- Machine-specific git identity (`user.name`/`user.email`, `core.editor`, `safe.directory`, the `gh` credential-helper
  stanzas) is **not** published to the shared `dotfiles` repo. It stays home-manager-owned, written to
  `~/.config/git/config-local`, which `dotfiles`' `~/.config/git/config` pulls in via
  `[include] path = ~/.config/git/config-local`. Neither side clobbers the other's file.
- To change the shared shell/git look and feel, edit `dotfiles` directly and bump the pinned commit (`nix flake update dotfiles`
  here; bump the `dotfilesRef` default in `devcontainer-features`' `shell-baseline` separately).

#### Pattern 2: Use Native Home-Manager Options

Use this for machine-specific or package-installation concerns a good native option already covers, e.g.:

```nix
programs.git = {
  enable = true;
  settings.user = {
    name = "Geoffrey Thomas";
    email = "you@example.com";
  };
};
```

#### Pattern 3: Keep A Literal File In The Repo

If you want to preserve an existing file mostly as-is and it isn't shared with devcontainers, create a per-user files
directory such as `users/thomasga/files/` and link it with `home.file`.

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

- `roles/desktop/gnome.nix` enables GNOME, GDM, and dconf settings. `roles/desktop/audio.nix` enables pipewire. `roles/desktop/power.nix` runs the logind idle inhibitor.
- `roles/common/flatpak.nix` enables Flatpak and Flatseal as optional platform services.
- `roles/common/gaming.nix` enables Steam as an optional gaming platform.
- `roles/common/base.nix` contains core system policy.
- `flake.nix` enables unfree packages needed by Chrome and Steam.
- `users/common/gui-apps.nix` enables Firefox and adds Fedora Media Writer, Bitwarden, Chrome, and Signal Desktop for any user that imports it.
- `users/thomasga/desktop.nix` opts `thomasga` into that shared GUI app set on desktop machines.
- `roles/common/users.nix` puts `thomasga` in `wheel`, which is why that user can administer enterprise-d.

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
nix eval .#nixosConfigurations."enterprise-d".config.age.identityPaths --json
nix build .#nixosConfigurations."enterprise-d".config.system.build.toplevel
```

Those commands work on non-NixOS hosts with Nix installed. `nixos-rebuild` itself only makes sense on NixOS or from a NixOS installer environment.

Then apply on the target NixOS system:

```bash
sudo nixos-rebuild dry-activate --flake .#enterprise-d
sudo nixos-rebuild switch --flake .#enterprise-d
```
