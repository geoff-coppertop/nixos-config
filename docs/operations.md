# Day-to-Day Operations

Setting up a workstation to work on this repo, applying changes, updating
machines, backups, and the checks that gate all of it.

Everything here assumes your shell is already at the repo root. Commands never
use `cd`; where a path is needed, use `git -C <repo>` or an absolute path.

## Workstation Setup

Mandatory before doing any provisioning or defining new machines. Complete it
once per development environment.

### Prerequisites

You need Nix 2.18 or later with flakes enabled. On NixOS this is already
configured.

- [ ] Nix is installed, from an official or up-to-date installer
- [ ] `nix --version` reports 2.18 or later
- [ ] Flakes are enabled in `~/.config/nix/nix.conf`:
      `experimental-features = nix-command flakes`
- [ ] You started a fresh shell after any installer or config change
- [ ] On multi-user installs you are in the `nix-users` group:
      `id -Gn | grep nix-users`

### Setting up on non-NixOS Linux or WSL

1. Install Nix with an official multi-user installer. Avoid distro packages if
   they lag far behind upstream. Start a fresh login shell afterward.
2. Enable flakes and the modern Nix CLI:

   ```bash
   mkdir -p ~/.config/nix
   printf 'experimental-features = nix-command flakes\n' >> ~/.config/nix/nix.conf
   ```

3. On WSL specifically, run commands inside the Linux filesystem and keep the age
   identity under `~/.config/agenix/` in the Linux home directory.
4. If the daemon socket permission fails, log out fully and back in. On systemd
   systems, verify `nix-daemon.service` is running.

### Confirming the environment works

```bash
nix --version                          # should be 2.18+
id -Gn | grep nix-users                # multi-user installs only
nix flake metadata path:$PWD           # verify flake resolution
nix develop -c bash -lc 'command -v age agenix pre-commit alejandra statix deadnix markdownlint'
```

All should succeed. The last one confirms the dev shell provides `age`, `agenix`,
and every lint tool.

## Dev Shell And Repo Tools

Enter the development shell — required for secret editing and lint tools:

```bash
nix develop
```

The flake exposes four apps (defined in `lib/apps.nix`). Use these rather than
invoking `agenix` or the scripts directly:

| Command | Script | What it does |
| --- | --- | --- |
| `nix run .#secret-edit -- <file>` | `tools/secret_edit.py` | Edit or create an `.age` secret in a temporary buffer |
| `nix run .#secret-rekey` | `tools/secret_rekey.py` | Re-encrypt every tracked secret after changing recipients |
| `nix run .#install` | `tools/install.py` | Install a machine: menu, then disko or SD-card flow |
| `nix run .#provision` | `tools/provision.py` | Lower-level per-provision-type driver used by `install.py` |

The remaining helpers in `tools/` are run directly:

| Script | What it does |
| --- | --- |
| `tools/enroll.py` | Enroll a machine: age identity, SSH keypair, repo wiring, rekey |
| `tools/bootstrap_ssh_key.py` | Create and encrypt an SSH keypair (used by `enroll.py`) |
| `tools/install_age_identity.py` | Install or rotate a host age identity on disk |
| `tools/check_no_plaintext_secrets.py` | Pre-commit guard against staging plaintext secrets |
| `tools/common.py` | Shared helpers for the scripts above |
| `tools/hibernate-test-report.sh` | Collect a hibernate/resume diagnostic report |

## Applying Changes

Always lint before rebuilding — it catches option renames and formatting errors
before the build fails partway through a switch:

```bash
nix develop -c pre-commit run --all-files
sudo nixos-rebuild switch --flake .#enterprise-d
```

### System updates (requires wheel)

| Machine | Command | Where to run |
| --- | --- | --- |
| `enterprise-d` | `sudo nixos-rebuild switch --flake .#enterprise-d` | On `enterprise-d` |
| `holodeck-01` | `sudo nixos-rebuild switch --flake .#holodeck-01` | Inside the WSL distro |
| `defiant` | `nixos-rebuild switch --flake .#defiant --target-host thomasga@defiant --use-remote-sudo` | Any machine with SSH and Nix |
| `enterprise-d` (remote) | `nixos-rebuild switch --flake .#enterprise-d --target-host thomasga@enterprise-d --use-remote-sudo` | Any machine with SSH and Nix |

### Automatic updates

`roles/common/base.nix` enables `system.autoUpgrade` for every host: it fetches
`github:geoff-coppertop/nixos-config#<hostname>` weekly and stages the result as
the next boot entry (`operation = boot`, `allowReboot = false`). Nothing reboots
automatically; apply the staged generation at your convenience. Because it tracks
the GitHub remote, only pushed commits are picked up.

On hosts with `custom.isLaptop = true` (currently `enterprise-d`) the upgrade
also skips while on battery — the same `ConditionACPower` gating used for NAS
backups.

Two opt-in modules add update mechanisms for specific hosts:

| Module | Option | Enabled on | What it does |
| --- | --- | --- | --- |
| `modules/flatpak.nix` | `custom.flatpak.enable` | `enterprise-d` | Weekly Flatpak update timer (AC-gated on laptops) plus update-on-activation |
| `modules/fwupd.nix` | `custom.fwupd.enable` | `enterprise-d` | fwupd daemon for LVFS firmware; apply with `fwupdmgr refresh && fwupdmgr update` |

### Monthly flake input update

```bash
nix flake update
sudo nixos-rebuild dry-activate --flake .#enterprise-d
sudo nixos-rebuild switch --flake .#enterprise-d
```

### User environment updates (self-serve, no sudo)

Each user can update their own home-manager environment without a full system
rebuild and without `sudo`. The flake exposes a
`homeConfigurations.<user>@<machine>` output for every user–machine pair.

```bash
# Apply your home-manager config on the current machine
home-manager switch --flake .#thomasga@enterprise-d

# Or from a branch / local checkout without switching the system
git checkout my-dotfiles-branch
home-manager switch --flake .#thomasga@enterprise-d
```

This works for any user, including users not in the `wheel` group. Only changes
that affect the system layer — new packages in `environment.systemPackages`,
firewall rules, new user accounts — require a wheel-gated `nixos-rebuild switch`.

## Backups

`roles/common/backups.nix` provides client-pushed restic backups to a NAS share,
mounted on demand over SMB or NFS. Backups run on a daily timer. On hosts marked
as laptops they only run when AC power is connected. If the NAS is unreachable,
the job exits cleanly.

It is imported by `roles/common/default.nix`, so every host already has it — a
host only needs to set `custom.backups`.

### How backups run

Each enabled entry gets its own systemd service (`nas-backup-<name>`) and timer
(`nas-backup-<name>-timer`). The service:

1. Triggers an automount of the NAS share.
2. Exits silently if the share is not reachable.
3. Initialises a restic repository on first run.
4. Backs up the configured paths (default: `/home/<name>`, excluding `.cache`).
5. Prunes old snapshots according to the retention policy — 7 daily, 4 weekly,
   12 monthly, 3 yearly by default. That progressively reduces granularity over
   time while keeping long-term coverage.

Each entry gets its **own restic repository**, and therefore its own
`restic-password` secret, keyed to the entry name rather than the machine.

### Enabling backups on a host

**1. Create the encrypted SMB credentials secret.** Add a recipient entry if the
file is new:

```nix
"thomasga/nas-smb-credentials.age".publicKeys = [enterprise-d offlineAdmin];
```

Then create or rotate it:

```bash
EDITOR=nano nix run .#secret-edit -- secrets/thomasga/nas-smb-credentials.age
```

Its plaintext contents must be exactly:

```text
username=<nas-username>
password=<nas-password>
```

Expose it at a known path in the host's `secrets.nix`:

```nix
age.secrets."thomasga/nas-smb-credentials".file =
  ../../secrets/thomasga/nas-smb-credentials.age;
```

**2. Create or rotate the restic password secret** for each backup entry:

```bash
EDITOR=nano nix run .#secret-edit -- secrets/thomasga/restic-password.age
```

Exactly one line containing the password. See
[docs/secrets.md § Secret Inventory](secrets.md#secret-inventory).

**3. Set the NAS coordinates and enable the entries** in the host configuration:

```nix
custom.isLaptop = true; # omit or set false for non-laptops

custom.backups = {
  enable = true;

  nas = {
    host = "192.168.1.x"; # or a hostname, if DNS resolves it
    share = "backups";
    credentialsFile = "/run/agenix/thomasga/nas-smb-credentials";
  };

  users.thomasga.enable = true;
};
```

Use `nas.protocol = "nfs"` and omit `credentialsFile` to switch to NFS.

`lib/nas.nix` holds the shared NAS constants (`ip`, `host`, `shares`); prefer
importing it over hardcoding the address.

**4. Rebuild the host.**

### Checking backup status

```bash
# List timers and see when the next backup runs
systemctl list-timers 'nas-backup-*'

# Run a backup immediately
sudo systemctl start nas-backup-thomasga.service

# View the backup log
journalctl -u nas-backup-thomasga.service

# List restic snapshots on the NAS
sudo restic --repo /mnt/nas-backups/thomasga/<hostname> snapshots
```

### Backing up service state outside `/home`

Override `paths` explicitly. Example from `defiant`, backing up Home Assistant:

```nix
custom.backups.users = {
  hass = {
    enable = true;
    paths = ["/var/lib/hass"];
    excludePatterns = ["/var/lib/hass/.storage/lovelace*"];
  };
};
```

`passwordFile` defaults to `/run/agenix/<name>/restic-password`; override it only
if the secret does not follow that convention.

### Backup limitations

- Snapper manages local btrfs snapshots for rollback. It is not involved in NAS
  backups.
- If SMB is unavailable at boot the automount fails silently, and the next timer
  invocation retries.
- Service state paths are case-sensitive and not always what the service name
  suggests — `defiant` backs up `/var/lib/AdGuardHome`, capitalized, because the
  lowercase path does not exist. Confirm with `ls` on the host before adding an
  entry.

## Validation Commands

Run these before switching on a real machine. They work on any Linux or WSL host
with Nix installed; `nixos-rebuild` itself only makes sense on NixOS or from a
NixOS installer environment.

```bash
nix develop -c pre-commit run --all-files
nix flake check --no-build
nix eval .#nixosConfigurations."enterprise-d".config.age.identityPaths --json
nix build .#nixosConfigurations."enterprise-d".config.system.build.toplevel
```

Then apply on the target NixOS system:

```bash
sudo nixos-rebuild dry-activate --flake .#enterprise-d
sudo nixos-rebuild switch --flake .#enterprise-d
```

### Building each host

```bash
# x86_64 machines — build natively
nix build .#nixosConfigurations.enterprise-d.config.system.build.toplevel
nix build .#nixosConfigurations.holodeck-01.config.system.build.toplevel

# aarch64 — needs binfmt emulation or a native/remote aarch64 builder
nix build .#nixosConfigurations.defiant.config.system.build.toplevel
nix build .#nixosConfigurations.defiant.config.system.build.sdImage
```

`enterprise-d` sets `boot.binfmt.emulatedSystems = ["aarch64-linux"]`, so it can
cross-build `defiant` locally, slowly. CI sidesteps this by building `defiant`
natively on an `ubuntu-24.04-arm` runner.

Use `nix flake check --no-build`, never bare `nix flake check`: the latter tries
to build every `nixosConfiguration` including the aarch64 one, which fails with a
platform mismatch on x86_64. Use `--no-build` for the eval-only check, then
`nix build` per platform.

## Lint, Format, And CI

All Nix files must pass:

- **alejandra** — formatter; run `alejandra .` to auto-format
- **statix** — linter, no antipatterns
- **deadnix** — no unused Nix bindings

All Markdown files must pass **markdownlint** (config in `.markdownlint.json`:
every default rule enabled, only `MD013` line-length disabled). The
`markdownlint` flake check runs `find . -name '*.md'` with no exclusions, so
`docs/`, `.claude/`, and host READMEs are all linted.

The `no-plaintext-secrets` pre-commit hook blocks staging anything that looks
like a raw secret. Never create files under `secrets/` except through
`nix run .#secret-edit`.

`.github/workflows/ci.yml` runs three jobs on every push to `master` and every
pull request, each posting its output as a PR comment before failing:

| Job | Command |
| --- | --- |
| `lint` | `nix develop -c pre-commit run --all-files` |
| `flake-check` | `nix flake check --no-build` |
| `build` | Matrix over all three hosts: `nix build .#nixosConfigurations.<host>.config.system.build.toplevel --no-link` |

The build job runs `enterprise-d` and `holodeck-01` on `ubuntu-latest` and
`defiant` on `ubuntu-24.04-arm`, freeing disk space first.
