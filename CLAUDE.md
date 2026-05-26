# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repository Does

This is a NixOS flake configuration for a single machine (Framework laptop, `x86_64-linux`). It manages the full system declaratively: disk layout, OS, hardware, secrets, home-manager user environment, and backup policy. Everything is committed; nothing is configured manually post-install.

## Common Commands

All commands assume Nix with flakes enabled (`experimental-features = nix-command flakes`).

**Enter the dev shell** (required for secret editing and lint tools):

```bash
nix develop
```

**Run all linters and format checks:**

```bash
nix develop -c pre-commit run --all-files
nix flake check
```

**Validate the build without switching:**

```bash
nix build .#nixosConfigurations.framework.config.system.build.toplevel
sudo nixos-rebuild dry-activate --flake .#framework
```

**Apply changes to the running system:**

```bash
sudo nixos-rebuild switch --flake .#framework
```

**Update flake inputs (monthly workflow):**

```bash
nix flake update
sudo nixos-rebuild dry-activate --flake .#framework
sudo nixos-rebuild switch --flake .#framework
```

**Edit or create an encrypted secret:**

```bash
EDITOR=nano nix run .#secret-edit -- secrets/thomasga/restic-password.age
```

**Re-encrypt all secrets after changing recipients in `secrets/secrets.nix`:**

```bash
nix run .#secret-rekey
```

**Verify age identity paths are correctly wired:**

```bash
nix eval .#nixosConfigurations.framework.config.age.identityPaths --json
```

## Code Architecture

The configuration is layered as a DAG of imports. Understanding which layer to edit is the main architectural decision:

```
flake.nix
  └── hosts/framework/          # machine-specific: hardware, disk, power
        └── roles/              # shared system policy: networking, GNOME, gaming
              └── modules/      # reusable NixOS features: backups, secrets, secure boot
                    └── users/thomasga/   # personal: dotfiles, shell, apps (home-manager)
                          └── users/common/  # opt-in shared user modules
```

**Placement rule (from README):**

- Machine behavior → `hosts/<machine>/` (machine-specific) or `roles/` (shared policy) or `modules/` (reusable feature)
- Personal workflow → `users/<name>/` (home-manager)
- Shared optional user feature → `users/common/` (imported by choice per user)

### Key Directories

| Path | Purpose |
|---|---|
| `flake.nix` | Single entry point; defines inputs, dev shell, checks, secret apps, and `nixosConfigurations.framework` |
| `hosts/framework/` | Hardware scan, disko disk layout, power/hibernate policy, machine imports |
| `roles/common/` | Base OS settings, single user (`thomasga`), NetworkManager Wi-Fi profiles, Steam, Flatpak |
| `roles/desktop/gnome.nix` | GNOME baseline, unwanted app removal, search-light extension |
| `modules/` | Opt-in NixOS features: backups, btrfs, snapper, agenix secrets, secure boot, TPM-LUKS, SSH known-hosts |
| `users/thomasga/` | Git, SSH, fish shell, GNOME dconf settings, VS Code, wallpaper |
| `users/common/` | Shared CLI tools (starship, zoxide, fzf, eza, bat), shared GUI apps (Firefox, Chrome, Bitwarden, Signal) |
| `lib/` | `checks.nix` (alejandra/statix/deadnix/markdownlint), `devshell.nix`, `ssh-hosts.nix`, `secret-apps.nix` |
| `secrets/` | Agenix `.age` encrypted files (safe to commit) + `secrets/secrets.nix` (recipient declarations) |
| `pkgs/` | Custom package definitions |
| `tools/` | Install scripts (non-Nix bash helpers for provisioning) |

### Custom Options

Modules expose behavior through `custom.*` options rather than direct NixOS options. Known options:

- `custom.backups` — enable per-user restic backups to NAS (SMB or NFS), AC-only gating for laptops
- `custom.isLaptop` — gates backup service on AC power when `true`
- `custom.cli.shell` — controls which shell user modules activate
- `custom.framework.enable` — Framework-specific driver/kernel configuration

### Secrets Architecture

Secrets never exist as plaintext on disk. The flow is:

1. Encrypted `.age` files committed to `secrets/` — safe to commit
2. `secrets/secrets.nix` declares which age public keys (hosts + offline admin) can decrypt each file
3. `modules/secrets.nix` exposes secrets at runtime via `age.secrets` → `/run/agenix/` (tmpfs)
4. NixOS modules and home-manager reference `/run/agenix/<name>` paths

The host age private key lives at `/var/lib/agenix/identity` on the deployed machine. The offline admin key is kept only in Bitwarden, never on machines.

Wi-Fi credentials use environment variable substitution: `psk = "$WIFI_AGT_HOME_PASSWORD"` in `roles/common/networking.nix`, with the variable sourced from the agenix secret at activation time.

### Adding a New Wi-Fi Network

Changes needed in four places: `secrets/secrets.nix`, `modules/secrets.nix`, `roles/common/networking.nix`, and the new `secrets/wifi/<name>.age` file. See README § Wi-Fi Pre-configuration for exact syntax.

### Flake Inputs

| Input | Purpose |
|---|---|
| `nixpkgs` (nixos-unstable) | Main package set and NixOS modules |
| `home-manager` | User environment management |
| `disko` | Declarative disk partitioning |
| `agenix` | Encrypted secrets in git |
| `lanzaboote` (v1.0.0) | Secure Boot via lanzaboote |
| `nix-flatpak` | Declarative Flatpak management |
| `pre-commit` | Lint checks in dev shell |

## Linting and Formatting Rules

All Nix files must pass:

- **alejandra** — Nix formatter (run `alejandra .` to auto-format)
- **statix** — Nix linter (no antipatterns)
- **deadnix** — no unused Nix bindings

All Markdown files must pass **markdownlint** (config in `.markdownlint.json`).

The pre-commit hook `no-plaintext-secrets` blocks staging any file that looks like a raw secret. Never create files under `secrets/` except through `nix run .#secret-edit`.

## Machine-Specific Notes

The only configured machine is `framework` (Framework laptop). See `hosts/framework/FRAMEWORK.md` for:

- TPM2 enrollment for LUKS auto-unlock (PCR selections, enrollment commands)
- Power/hibernate behavior table (lid close, idle timings, suspend-then-hibernate)
- Post-install checklist

The current user is `thomasga` (Geoffrey Thomas). The home-manager attachment is declared directly in `flake.nix` under `home-manager.users.thomasga`.
