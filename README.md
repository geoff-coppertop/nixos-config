# NixOS Config

This repo is the source of truth for machine setup, user setup, secrets wiring, and update policy. There are two main tasks it supports: provisioning a machine already defined here, and adding an entirely new machine to the repo.

## Contents

- [Repository Model](#repository-model)
- [Machine Naming](#machine-naming)
- [WSL Setup](#wsl-setup)
  - [Option A: Pre-provision from enterprise-d (recommended)](#option-a-pre-provision-from-enterprise-d-recommended)
  - [Option B: Bootstrap first, enroll secrets after](#option-b-bootstrap-first-enroll-secrets-after)
  - [Rebuilding an existing install](#rebuilding-an-existing-install)
- [Updating Machines](#updating-machines)
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
  - [Phase 2 — First full deploy and identity extraction](#phase-2--first-full-deploy-and-identity-extraction)
  - [Phase 3 — Service setup](#phase-3--service-setup)
- [Defining a New Machine](#defining-a-new-machine)
  - [Repository Structure](#repository-structure)
  - [Secrets and SSH Setup](#secrets-and-ssh-setup)
- [Reference](#reference)
  - [Secrets Management](#secrets-management)
  - [Wi-Fi Pre-configuration](#wi-fi-pre-configuration)
  - [Hibernation And Power](#hibernation-and-power)
  - [Change GNOME Or Kernel Policy Later](#change-gnome-or-kernel-policy-later)
  - [Users And Configuration](#users-and-configuration)
  - [Dotfiles And Shell Scripts](#dotfiles-and-shell-scripts)
  - [Desktop Application Policy](#desktop-application-policy)
  - [Obsidian MCP Integration](#obsidian-mcp-integration)
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

There are two paths. **Option A** (recommended) does all config work on `enterprise-d` first so secrets are active from the very first WSL boot. **Option B** bootstraps the machine first and wires up secrets afterward.

**Already have a NixOS WSL distro running?** Skip to [Rebuilding an existing install](#rebuilding-an-existing-install).

### Option A: Pre-provision from enterprise-d (recommended)

**Step 1 — Enroll the machine on enterprise-d:**

```bash
nix develop -c bash tools/enroll-machine.sh holodeck-01
```

At the age identity prompt choose **2) Generate a new keypair here**. The script:

- Generates an age keypair at `~/.config/agenix/holodeck-01.age`
- Generates and age-encrypts an SSH keypair (private key shredded immediately)
- Creates `hosts/holodeck-01/secrets.nix` and wires it into `configuration.nix`
- Updates `secrets/secrets.nix` and `lib/ssh-hosts.nix`
- Re-keys all secrets so `holodeck-01` is a recipient

**Step 2 — Commit and push:**

```bash
git add -p
git commit -m "feat: enroll holodeck-01"
git push
```

The bootstrap script applies the flake from GitHub, so the config must be pushed before continuing.

**Step 3 — Transfer the age identity to Windows:**

Copy `~/.config/agenix/holodeck-01.age` from `enterprise-d` to your Windows machine (shared drive, USB, or `scp`). Keep it out of cloud-synced folders; it will be deleted after install.

**Step 4 — Run the bootstrap script:**

No repo clone needed — run directly from Windows Terminal (PowerShell), replacing the path with wherever you saved the age identity file:

```powershell
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/geoff-coppertop/nixos-config/master/tools/install-wsl.ps1'))) -AgeIdentityPath "E:\holodeck-01.age"
```

If you already have the repo cloned on Windows:

```powershell
.\tools\install-wsl.ps1 -AgeIdentityPath "E:\holodeck-01.age"
```

The script downloads NixOS-WSL, imports the distro, installs the identity at `/var/lib/agenix/identity`, and applies the `holodeck-01` flake from GitHub.

> **Testing a feature branch before it is merged to master?** Pass `-FlakeBranch`:
>
> ```powershell
> & ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/geoff-coppertop/nixos-config/<branch>/tools/install-wsl.ps1'))) -AgeIdentityPath "E:\holodeck-01.age" -FlakeBranch "<branch>"
> ```

**Step 5 — Post-boot cleanup:**

```powershell
# Delete the age private key from Windows once the distro is running
Remove-Item "E:\holodeck-01.age"
```

Inside WSL:

```bash
# Authenticate GitHub CLI (browser/token flow — no SSH key needed)
gh auth login

# Collect the SSH host public key and pin it in lib/ssh-hosts.nix on enterprise-d
ssh-keyscan -t ed25519 holodeck-01
```

**Enabling backups (optional — can be done any time after setup):**

In `hosts/holodeck-01/configuration.nix`, flip the backups flags:

```nix
custom.backups = {
  enable = true;
  nas    = { ... };                      # already present
  users.thomasga.enable = true;          # change false → true
};
```

Also add `./secrets.nix` to the `users/thomasga/headless.nix` imports so `RESTIC_PASSWORD_FILE` is set in the user session. Then commit, push, and rebuild inside WSL:

```bash
sudo nixos-rebuild switch --flake github:geoff-coppertop/nixos-config#holodeck-01
```

---

### Option B: Bootstrap first, enroll secrets after

No repo clone needed — run directly from Windows Terminal (PowerShell):

```powershell
irm 'https://raw.githubusercontent.com/geoff-coppertop/nixos-config/master/tools/install-wsl.ps1' | iex
```

> **Note:** `irm ... | iex` does not support parameters. To pass `-AgeIdentityPath` or `-FlakeBranch`, use the scriptblock form from Option A Step 4.

If you already have the repo cloned on Windows:

```powershell
.\tools\install-wsl.ps1
```

At the age identity prompt choose **2) Skip**. The script imports the NixOS-WSL base distro but skips `nixos-rebuild` — the holodeck-01 config uses agenix secrets, so the rebuild requires the age private key to be installed first.

**Step 1 — Generate the age identity inside holodeck-01:**

```bash
wsl -d NixOS
sudo age-keygen -o /var/lib/agenix/identity   # prints: Public key: age1...
sudo chmod 400 /var/lib/agenix/identity
```

**Step 2 — Enroll the identity on enterprise-d:**

```bash
nix develop -c bash tools/enroll-machine.sh holodeck-01
# Choose: 1) I have the age public key  →  paste the age1... printed above
```

The script updates `secrets/secrets.nix`, generates and encrypts a per-machine SSH keypair, updates all config files, and re-keys secrets.

Commit and push:

```bash
git add -p
git commit -m "feat: enroll holodeck-01"
git push
```

**Step 3 — Apply the config inside holodeck-01:**

```bash
wsl -d NixOS
sudo nixos-rebuild switch --flake github:geoff-coppertop/nixos-config#holodeck-01
```

---

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

| Machine | Update command | Where to run |
| --- | --- | --- |
| `enterprise-d` | `sudo nixos-rebuild switch --flake .#enterprise-d` | On `enterprise-d` |
| `holodeck-01` | `sudo nixos-rebuild switch --flake .#holodeck-01` | Inside the WSL distro |
| `defiant` | `nixos-rebuild switch --flake .#defiant --target-host thomasga@defiant --use-remote-sudo` | From any machine with SSH + Nix |
| `enterprise-d` (remote) | `nixos-rebuild switch --target-host thomasga@enterprise-d --flake .#enterprise-d` | From any machine with SSH + Nix |

Monthly flake update workflow (run on `enterprise-d`):

```bash
nix flake update
sudo nixos-rebuild dry-activate --flake .#enterprise-d
sudo nixos-rebuild switch --flake .#enterprise-d
```

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
   sudo bash tools/install-age-identity.sh --file ~/.config/agenix/enterprise-d.age
   ```

   Pass `--shred` to erase the source file after copying.

7. On an already-installed machine, install or rotate the dedicated host identity in place with:

   ```bash
   sudo bash tools/install-age-identity.sh --file ~/.config/agenix/enterprise-d.age \
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

`secrets/thomasga/obsidian-api-key.age` decrypts to exactly one plaintext line — the API key shown in Obsidian's Local REST API plugin settings:

```text
your-api-key-here
```

Do not add a key name, quotes, or any other prefix. Just the raw key value on a single line.

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

Use `tools/enroll-machine.sh` to generate a per-machine SSH keypair, encrypt it as an agenix secret, and wire everything up automatically:

```bash
nix develop -c bash tools/enroll-machine.sh <machine-name>
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

`tools/enroll-machine.sh` populates `userPublicKey` as part of enrollment. To pin `publicKey` after first boot, collect the host key and paste it in:

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

- Backups target `/home/<user>` by default. For service state outside `/home`, override `paths` explicitly. Example from `defiant` backing up Home Assistant and Syncthing:

  ```nix
  custom.backups.users = {
    hass = {
      enable = true;
      paths = ["/var/lib/hass"];
      excludePatterns = ["/var/lib/hass/.storage/lovelace*"];
      passwordFile = "/run/agenix/defiant/restic-password";
    };
  };
  ```

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

After the system boots:

1. **Enroll TPM2 for LUKS auto-unlock** (see [TPM Auto-Unlock After Install](#tpm-auto-unlock-after-install))
2. **Collect the SSH host public key** and add it to `lib/ssh-hosts.nix` (see [Collect Host SSH Public Key After Deploy](#collect-host-ssh-public-key-after-deploy))
3. **Generate and install your SSH login credentials** (see [Generate SSH Login Credentials](#generate-ssh-login-credentials))
4. **Test hibernation** (see [Hibernation And Power](#hibernation-and-power))
5. **Validate the system** (see [Validation Commands](#validation-commands))

## Provisioning defiant (Raspberry Pi 4)

defiant is a headless aarch64 homelab server running Traefik, Home Assistant, Syncthing, AdGuard Home, Zigbee2MQTT, Z-Wave JS, and ADS-B.

### Phase 0 — Preparation (on enterprise-d, before touching the Pi)

**Enroll the machine:**

```bash
nix develop -c bash tools/enroll-machine.sh defiant
# Choose: 2) Generate a new keypair here
```

**Create service secrets** (one by one, storing passphrases in Bitwarden):

```bash
EDITOR=nano nix run .#secret-edit -- secrets/defiant/cloudflare-api-token.age
# Contents: CF_DNS_API_TOKEN=<Cloudflare Zone:DNS:Edit token for coppertop.ca>

EDITOR=nano nix run .#secret-edit -- secrets/defiant/nas-smb-credentials.age
# Contents: username=<nas-user>\npassword=<nas-password>

EDITOR=nano nix run .#secret-edit -- secrets/defiant/restic-password.age
# Contents: single passphrase line
```

**Build and flash the SD card** (cross-compile from x86\_64 — takes several minutes):

```bash
nix build .#nixosConfigurations.defiant.config.system.build.sdImage
zstd -d result/sd-image/*.img.zst -o /tmp/defiant.img
lsblk                            # identify the SD card device
sudo dd if=/tmp/defiant.img of=/dev/sdX bs=4M status=progress conv=fsync
```

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

### Phase 2 — First full deploy and identity extraction

```bash
nixos-rebuild switch --flake .#defiant \
  --target-host thomasga@defiant \
  --use-remote-sudo
```

After deploy, extract Zigbee network key and Syncthing identity **before pairing any devices**:

```bash
# Zigbee network key (extract before pairing any devices — losing it requires re-pairing all)
ssh thomasga@defiant "sudo cat /var/lib/zigbee2mqtt/configuration.yaml" | grep network_key
EDITOR=nano nix run .#secret-edit -- secrets/defiant/zigbee-network-key.age
# Contents: paste the full network_key line

# Syncthing identity (extract before pairing any devices — losing it changes the device ID)
ssh thomasga@defiant "sudo cat /var/lib/syncthing/key.pem" > /tmp/st-key.pem
ssh thomasga@defiant "sudo cat /var/lib/syncthing/cert.pem" > /tmp/st-cert.pem
EDITOR=nano nix run .#secret-edit -- secrets/defiant/syncthing-key.age   # paste key.pem
EDITOR=nano nix run .#secret-edit -- secrets/defiant/syncthing-cert.age  # paste cert.pem
shred -u /tmp/st-key.pem /tmp/st-cert.pem
```

Uncomment the `certFile`/`keyFile` lines in `hosts/defiant/configuration.nix` and add the secret declarations to `hosts/defiant/secrets.nix`. Rekey, commit, push, redeploy.

### Phase 3 — Service setup

| Service | URL | Action |
| --- | --- | --- |
| AdGuard Home | `https://dns.coppertop.ca` | Complete setup wizard; upstream DNS: `127.0.0.1:5335` |
| Home Assistant | `https://homeassistant.coppertop.ca` | Restore backup or complete onboarding |
| Syncthing | `https://syncthing.coppertop.ca` | Add client device IDs; share Obsidian vault folder |
| Zigbee2MQTT | `https://zigbee.coppertop.ca` | Enable join mode; pair devices (see notes below) |
| Z-Wave JS | HA → Integrations | Connect to `ws://localhost:3000`; include Z-Wave devices |
| Bambu Lab | HA → Integrations | Add integration; choose LAN mode (disables Handy app) or cloud mode |

**IKEA device pairing notes:**

- **Somrig button** — pair normally; automations should use `initial_press` only (`long_press`/`double_press` unreliable); re-pair after any OTA update.
- **VALLHORN/PARASOLL** — if the interview fails, retry pairing. Do not set occupancy timeout below 90 s on any IKEA motion sensor.
- **E1745 motion sensor** — do **not** apply OTA firmware; it disables motion detection.
- **STARKVIND air purifier** — no known issues; pair normally.

### DNS bypass

Clients needing unfiltered DNS (skips AdGuard ad-blocking, retains `coppertop.ca` resolution):

```bash
dig @defiant -p 5335 homeassistant.coppertop.ca
```

Point a device at `<defiant-ip>:5335` in its DNS settings to bypass AdGuard permanently.

### Syncthing non-NixOS clients

The Syncthing hub on defiant speaks the standard Syncthing protocol. Windows machines pair without any NixOS involvement:

```powershell
winget install Syncthing.Syncthing   # or use SyncTrayzor for a system-tray wrapper
```

Open `https://syncthing.coppertop.ca`, add the Windows device ID, share the Obsidian vault folder. Accept the share request on the Windows client.

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
nix develop -c bash tools/enroll-machine.sh <machine-name>
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

To add `alice`:

1. Create `users/alice/desktop.nix` (or `headless.nix` for servers/WSL).
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
home-manager.users.alice = {
  imports = [./users/alice/desktop.nix];  # or headless.nix for servers/WSL
};
```

### Assign A User To One Host Or All Hosts

- Put the Unix account in a shared module if the user should exist on all hosts.
- Put the Unix account in a host-specific import if the user should exist only on one machine.
- Attach the user's home-manager module only on the hosts where that user's environment should appear.

### Dotfiles And Shell Scripts

Do not manually copy dotfiles after installation. Manage them through home-manager.

Use one of two patterns.

#### Pattern 1: Use Native Home-Manager Options

Current Git config already follows this pattern:

```nix
programs.git = {
  userName = "Geoffrey Thomas";
  userEmail = "you@example.com";
};
```

Use this pattern first when a good native option exists.

#### Pattern 2: Keep A Literal File In The Repo

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

### Obsidian MCP Integration

`custom.ai.obsidian.enable = true` (set in `users/thomasga/default.nix`) wires Claude Code to an Obsidian vault via two components:

1. **`pkgs/obsidian-local-rest-api.nix`** — the [Local REST API](https://github.com/coddingtonbear/obsidian-local-rest-api) community plugin, copied into the vault at `~/Documents/obsidian/.obsidian/plugins/obsidian-local-rest-api/` by a home-manager activation hook in `users/thomasga/obsidian.nix`.
2. **`pkgs/mcp-obsidian.nix`** — the [mcp-obsidian](https://github.com/MarkusPfundstein/mcp-obsidian) Python stdio MCP server, wrapped in a launcher that reads the API key from `/run/agenix/thomasga/obsidian-api-key` and exports it as `OBSIDIAN_API_KEY`. The launcher path is written to `~/.claude/.mcp.json` by home-manager.

#### First-time activation

Before running `nixos-rebuild switch` for the first time with this feature, fill in the real hashes for `pkgs/obsidian-local-rest-api.nix` (which currently uses `lib.fakeHash` as placeholders):

```bash
# Fetch the source hash
nix-prefetch-github coddingtonbear obsidian-local-rest-api --rev 4.1.3

# Build to get the npm deps hash — the build will fail but print the expected hash
nix build .#legacyPackages.x86_64-linux.callPackage\ ./pkgs/obsidian-local-rest-api.nix\ \{\} 2>&1 | grep "got:"
```

Replace both `lib.fakeHash` values in `pkgs/obsidian-local-rest-api.nix` with the output.

#### API key setup

The API key must be obtained from Obsidian after the plugin is installed:

1. Run `nixos-rebuild switch --flake .#enterprise-d` — the activation hook copies the plugin into the vault.
2. Open Obsidian, go to **Settings → Community Plugins**, enable **Local REST API**.
3. Copy the API key shown in the plugin's settings pane.
4. Store it as an agenix secret (one line, no quotes):
   ```bash
   EDITOR=nano nix run .#secret-edit -- secrets/thomasga/obsidian-api-key.age
   ```
5. Run `nixos-rebuild switch --flake .#enterprise-d` again — agenix deploys the secret and home-manager writes `~/.claude/.mcp.json`.

#### Verification

```bash
# Confirm the MCP config points to the launcher
cat ~/.claude/.mcp.json

# Confirm the launcher binary exists and is executable
ls -la $(jq -r '.mcpServers.obsidian.command' ~/.claude/.mcp.json)

# Confirm the API key secret is deployed
ls -la /run/agenix/thomasga/obsidian-api-key

# Test the MCP server directly (Obsidian must be running with the plugin enabled)
$(jq -r '.mcpServers.obsidian.command' ~/.claude/.mcp.json)
```

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
