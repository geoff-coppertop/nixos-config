# NixOS Config

This repo is the source of truth for machine setup, user setup, secrets wiring, and update policy.

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

## Current Host

The active machine in this repo is `framework`.

- Host entrypoint: `hosts/framework/configuration.nix`
- Hardware: `hosts/framework/hardware.nix`
- Power tuning and hibernation policy: `hosts/framework/power.nix`
- Disk layout: `hosts/framework/disko.nix`
- Flake entry: `flake.nix`

## Developer Checks

This flake exposes a development shell with the local formatting, lint,
and secret-management tools used by the Git hooks.

### Prerequisites

You need Nix (version 2.18+) with flakes enabled. If working on Ubuntu, Fedora,
Debian, or WSL, follow the setup guide below. On a NixOS system, these should
already be configured.

**Checklist:**

- [ ] Nix is installed (from an official or up-to-date installer)
- [ ] Nix version is 2.18 or later: `nix --version`
- [ ] Flakes are enabled in `~/.config/nix/nix.conf`: `experimental-features = nix-command flakes`
- [ ] You've started a fresh shell after any installer/config changes
- [ ] Multi-user installs have you in the `nix-users` group: `id -Gn | grep nix-users`

### Setting Up On Non-NixOS Linux Or WSL

If the checklist above isn't complete, follow these steps:

1. Install Nix with an official multi-user installer. Avoid distro packages if
   they lag far behind upstream. Start a fresh login shell afterward.

2. Enable flakes and the modern Nix CLI:

```bash
mkdir -p ~/.config/nix
printf 'experimental-features = nix-command flakes\n' >> ~/.config/nix/nix.conf
```

3. For WSL specifically: run commands inside the Linux filesystem and keep the
   age identity under `~/.config/agenix/` in the Linux home directory.

4. If the daemon socket permission fails, fully log out and log back in. On
   systemd systems, verify `nix-daemon.service` is running.

### Verifying Your Setup

Run these checks to confirm everything is working:

```bash
cd /home/thomasg/builds/geoff-coppertop/nixos-config
nix --version                          # should be 2.18+
id -Gn | grep nix-users                # multi-user only
nix flake metadata path:$PWD           # verify flake resolution
nix develop -c bash -lc 'command -v age agenix pre-commit alejandra statix deadnix markdownlint'
```

All commands should succeed. The final one verifies the dev shell includes
`age`, `agenix`, and all lint tools.

### Using The Dev Shell And Repo Tools

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

## Secrets

This repo uses agenix for committed secrets and Bitwarden for recovery
material.

Do not work on secrets until you've completed "Verifying Your Setup" above and
confirmed that `nix develop` exposes both `age` and `agenix`.

Runtime decryption on NixOS uses the dedicated age private key at
`/var/lib/agenix/identity`. That path is configured in `modules/secrets.nix`.

### First-Time Secret Bootstrap

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

If `EDITOR` is empty, set it before using `nix run .#secret-edit`.

2. Generate a dedicated age identity outside the repo:

```bash
mkdir -p ~/.config/agenix
chmod 700 ~/.config/agenix
age-keygen -o ~/.config/agenix/nixos-config.age
chmod 600 ~/.config/agenix/nixos-config.age
```

3. Copy the public key printed by `age-keygen` into `secrets/secrets.nix`
and replace the placeholder `age1REPLACE_ME` value.

4. Store the private key or its recovery material in Bitwarden.

5. Before the first `nixos-install`, copy the private key into the mounted
target so the installed system can decrypt secrets on first boot:

```bash
sudo install -D -m 600 ~/.config/agenix/nixos-config.age /mnt/var/lib/agenix/identity
```

6. On an already-installed machine, install or rotate the dedicated identity
in place with:

```bash
sudo install -D -m 600 ~/.config/agenix/nixos-config.age /var/lib/agenix/identity
```

### Creating Or Rotating Secrets

Never create plaintext files under `secrets/`. Use the helper command so the
plaintext only exists in a temporary editor buffer.

For a brand-new secret:

1. Add a recipient entry to `secrets/secrets.nix`. Example:

```nix
"thomasga/nas-smb-credentials.age".publicKeys = [ thomasga ];
```

2. Create or edit the encrypted file:

```bash
EDITOR=vim nix run .#secret-edit -- secrets/thomasga/nas-smb-credentials.age
```

3. If NixOS or home-manager needs a runtime path for that secret, expose it
through `age.secrets` in `modules/secrets.nix` or another imported module.

To rotate an existing secret:

```bash
EDITOR=vim nix run .#secret-edit -- secrets/thomasga/restic-password.age
```

After changing recipients in `secrets/secrets.nix`, re-encrypt every tracked
secret with:

```bash
nix run .#secret-rekey
```

### Exact Secret Contents

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

### What May Be Committed

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

## Backups

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
"thomasga/nas-smb-credentials.age".publicKeys = [ thomasga ];
```

Then create or rotate the encrypted file:

```bash
EDITOR=vim nix run .#secret-edit -- secrets/thomasga/nas-smb-credentials.age
```

Its plaintext contents must be:

```
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
sudo nixos-rebuild switch --flake /etc/nixos-config#<hostname>
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

## First Install

### 1. Create a NixOS Installer USB From Fedora 44

Preferred path:

1. Download the latest NixOS graphical ISO for `x86_64-linux`.
2. Verify the checksum from the NixOS release page.
3. Write the image with Fedora Media Writer.

Advanced manual path:

1. Identify the USB device with `lsblk`.
2. Unmount any mounted partitions for that USB device.
3. Write the ISO directly:

```bash
sudo dd if=./nixos-graphical.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Replace `/dev/sdX` with the whole USB device, not a partition.

### 2. Create a NixOS Installer USB From Windows

Use Fedora Media Writer.

1. Download the latest NixOS graphical ISO for `x86_64-linux`.
2. Verify the published checksum.
3. Flash the ISO to a USB stick with Rufus or Fedora Media Writer.

### 3. Boot the Framework From USB

1. Insert the USB stick.
2. Power on the Framework and open the boot menu.
3. Boot the NixOS installer USB in UEFI mode.
4. Leave Secure Boot off for the first install. Secure Boot is enabled later through lanzaboote after the system is installed.

### 4. Provision the Disk Layout (Destructive)

Before provisioning, create a temporary file with your LUKS root passphrase:

```bash
echo "your-secure-passphrase-here" | sudo tee /tmp/encryption-password
chmod 600 /tmp/encryption-password
```

Then run disko:

```bash
sudo nix run github:nix-community/disko -- --mode destroy,format,mount ./hosts/framework/disko.nix
```

After disko completes, securely erase the temporary file (its contents are now written to the encrypted partition):

```bash
sudo shred -vfz -n 3 /tmp/encryption-password
```

This host layout creates:

- EFI system partition at `/boot/efi`
- ext4 `/boot`
- swap partition for hibernation resume
- encrypted btrfs root with `@` and `@home` subvolumes

### 5. Clone the Repo Into the Mounted Target

```bash
nix-shell -p git
mkdir -p /mnt/etc
git clone <your-repo-url> /mnt/etc/nixos-config
cd /mnt/etc/nixos-config
```

If you are installing from a local checkout instead of cloning in the installer, copy that checkout into `/mnt/etc/nixos-config` after the target disks are mounted.

### 6. Prepare Secrets and Recovery Material

Follow the `Secrets` section before installing.

Before running `nixos-install`, confirm all of the following:

1. `secrets/secrets.nix` contains the real public key, not `age1REPLACE_ME`.
2. Every required secret already exists as an encrypted `.age` file.
3. The dedicated age private key has been copied into the mounted target:

```bash
sudo install -D -m 600 ~/.config/agenix/nixos-config.age /mnt/var/lib/agenix/identity
```

4. Bitwarden contains the recovery copy of the dedicated age private key.

### 7. Install the System

After disks are mounted and secrets are in place:

```bash
sudo nixos-install --flake /mnt/etc/nixos-config#framework
```

### 8. Enroll Secure Boot After Install

This repo uses lanzaboote.

1. Ensure the installed system has `/etc/secureboot` populated with your Secure Boot keys.
2. Rebuild the system.
3. Enroll the keys in firmware.
4. Turn Secure Boot on in UEFI.
5. Reboot and verify the system boots through the signed path.

Keep copies of Secure Boot key material in a safe recovery location. Bitwarden is a reasonable place for the recovery instructions and escrowed material if that matches your threat model.

## TPM-Based LUKS Encryption

This repo encrypts the root filesystem with LUKS and seals it to the TPM 2.0 chip in your Framework laptop.

### Encryption At Install Time

The disko configuration creates an encrypted root partition. During provisioning (step 4 above), you provide a LUKS passphrase in `/tmp/encryption-password`. This passphrase will unlock the root filesystem if the TPM is unavailable or tampered with.

**Important:** Write down or save this passphrase in a secure location outside the machine. You will need it if:
- The TPM is reset or replaced
- The firmware is updated and TPM state is cleared
- You boot from a rescue USB and need to manually unlock the disk

### TPM Auto-Unlock After Install

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

### Verify TPM Enrollment

To check that TPM enrollment is active:

```bash
sudo systemd-cryptenroll /dev/disk/by-partlabel/root --json | jq '.[] | select(.type=="tpm2")'
```

A non-empty result confirms TPM2 enrollment is active.

### Change Or Reset The LUKS Passphrase

To change the passphrase while the system is running:

```bash
sudo cryptsetup luksChangeKey /dev/disk/by-partlabel/root
```

To wipe the passphrase slot and rely entirely on TPM2 unlock:

```bash
sudo systemd-cryptenroll /dev/disk/by-partlabel/root --wipe-slot=password
```

### TPM Recovery And Troubleshooting

If the system does not auto-unlock at boot:

1. **At the initrd prompt:** You will be asked for the LUKS passphrase. Enter the passphrase you created during install.
2. **If you forgot the passphrase:** Boot from a NixOS rescue USB and use standard LUKS recovery tools.
3. **If the TPM appears broken:** Re-enroll the passphrase and optionally re-enroll TPM2 after the system boots.
4. **If Secure Boot or firmware state changes:** The TPM may not unlock automatically. Either provide the passphrase or re-enroll TPM after boot.

Store your LUKS passphrase in Bitwarden or another secure offline location for disaster recovery.

### Recovery

## Hibernation And Power

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

## Updating The System

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

## Adding A New Machine

To add a second machine, for example `desktop`:

1. Create `hosts/desktop/`.
2. Add `hosts/desktop/configuration.nix`.
3. Add `hosts/desktop/hardware.nix`.
4. Add `hosts/desktop/power.nix`.
5. Add `hosts/desktop/disko.nix` if the machine should be provisioned by this repo.
6. Register `desktop` under `nixosConfigurations` in `flake.nix`.

Concrete shape:

```nix
nixosConfigurations.desktop = nixpkgs.lib.nixosSystem {
	inherit system;
	modules = [
		./hosts/desktop/configuration.nix
		./hosts/desktop/disko.nix
		disko.nixosModules.disko
		home-manager.nixosModules.home-manager
		agenix.nixosModules.default
		lanzaboote.nixosModules.lanzaboote
	];
};
```

## Users, User Assignment, And New Users

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

## Dotfiles And Shell Scripts

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

## Desktop Application Policy

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
- `roles/common/base.nix` enables unfree packages and contains core system policy.
- `roles/common/base.nix` allows the unfree packages needed by Chrome and Steam.
- `users/common/gui-apps.nix` adds Firefox, Fedora Media Writer, Bitwarden, and Chrome for any user that imports it.
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

In this repo, that policy lives in `roles/common/base.nix`.

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

## Validation

Before switching on a real machine, use a Linux or WSL environment with Nix
installed.

```bash
nix develop -c pre-commit run --all-files
nix flake check
nix eval .#nixosConfigurations.framework.config.age.identityPaths --json
nix build .#nixosConfigurations.framework.config.system.build.toplevel
```

Those commands work on non-NixOS hosts with Nix installed. `nixos-rebuild`
itself only makes sense on NixOS or from a NixOS installer environment.

Then apply on the target NixOS system:

```bash
sudo nixos-rebuild dry-activate --flake .#framework
sudo nixos-rebuild switch --flake .#framework
```
