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
nix build .#nixosConfigurations.enterprise-d.config.system.build.toplevel
sudo nixos-rebuild dry-activate --flake .#enterprise-d
```

**Apply changes to the running system:**

```bash
sudo nixos-rebuild switch --flake .#enterprise-d
```

**Update flake inputs (monthly workflow):**

```bash
nix flake update
sudo nixos-rebuild dry-activate --flake .#enterprise-d
sudo nixos-rebuild switch --flake .#enterprise-d
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
nix eval .#nixosConfigurations.enterprise-d.config.age.identityPaths --json
```

## Code Architecture

The configuration is layered as a DAG of imports. Understanding which layer to edit is the main architectural decision:

```text
flake.nix
  └── hosts/enterprise-d/          # machine-specific: hardware, disk, power
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
| --- | --- |
| `flake.nix` | Single entry point; defines inputs, dev shell, checks, secret apps, and `nixosConfigurations.enterprise-d` |
| `hosts/enterprise-d/` | Hardware scan, disko disk layout, power/hibernate policy, machine imports |
| `roles/common/` | Base OS settings, single user (`thomasga`), NetworkManager Wi-Fi profiles, Steam, Flatpak |
| `roles/desktop/gnome.nix` | GNOME baseline, unwanted app removal, search-light extension |
| `roles/dev/` | Dev tooling: GitHub CLI, podman/podman-compose |
| `modules/` | Opt-in NixOS features: backups, btrfs, snapper, agenix secrets, secure boot, TPM-LUKS, SSH known-hosts |
| `users/thomasga/` | Git, SSH, fish shell, GNOME dconf settings, VS Code, wallpaper |
| `users/common/` | Shared CLI tools (starship, zoxide, fzf, eza, bat), shared GUI apps (Firefox, Chrome, Bitwarden, Signal) |
| `lib/` | `checks.nix` (alejandra/statix/deadnix/markdownlint), `devshell.nix`, `ssh-hosts.nix`, `secret-apps.nix` |
| `secrets/` | Agenix `.age` encrypted files (safe to commit) + `secrets/secrets.nix` (recipient declarations) |
| `pkgs/` | Custom package build (`framework-control` GUI) |
| `tools/` | Install scripts (non-Nix bash helpers for provisioning) |

### Custom Options

Modules expose behavior through `custom.*` options rather than direct NixOS options. Known options:

- `custom.backups` — enable per-user restic backups to NAS (SMB or NFS), AC-only gating for laptops
- `custom.isLaptop` — defined in `roles/common/base.nix`; gates AC-power-sensitive maintenance jobs (NAS backups, NixOS auto-upgrade, Flatpak auto-update) when `true`
- `custom.cli.shell` — controls which shell user modules activate
- `custom.framework.enable` — Framework-specific driver/kernel config (fingerprint reader, keyboard brightness, charge limit) plus the `framework-control` GUI service from `pkgs/`
- `custom.secureBoot.enable` — lanzaboote Secure Boot
- `custom.btrfs.enable` — btrfs compression on root filesystem
- `custom.snapper.enable` — snapper btrfs snapshot schedules
- `custom.tpmLuks.enable` — TPM2-sealed LUKS root unlock
- `custom.networkDrives` — auto-mount SMB shares at graphical login; configure `nas.host` and per-user `shares.<name>` entries
- `custom.appearance.darkMode` — system-wide dark mode (home-manager, defined in `users/common/appearance.nix`)
- `custom.ai.claude.enable` / `custom.ai.copilot.enable` — Claude AI tools / GitHub Copilot integration in VS Code
- `custom.debugProbes.enable` — udev rules for USB JTAG/SWD debug probes (ST-Link, J-Link, FTDI, CMSIS-DAP incl. Raspberry Pi Debug Probe); required so rootless devcontainers that bind-mount `/dev/bus/usb` can access the hardware as a non-root user

### Home-manager Patterns

**VS Code:** `programs.vscode` uses `profiles.default` for `extensions` and `userSettings`; `argvSettings` (maps to `argv.json`, e.g. `disable-hardware-acceleration = true`) lives at the top level, not inside the profile.

**Overriding app launch flags:** Use `xdg.desktopEntries.<name>` in home-manager to replace a package's `.desktop` file with a modified `exec` line (e.g. adding `--disable-gpu`). Place it alongside the package declaration in `users/common/` or `users/thomasga/`.

### Secrets Architecture

Secrets never exist as plaintext on disk. The flow is:

1. Encrypted `.age` files committed to `secrets/` — safe to commit
2. `secrets/secrets.nix` declares which age public keys (hosts + offline admin) can decrypt each file
3. `age.secrets.*` entries declared in host/role files are decrypted at activation time into `/run/agenix/` (tmpfs)
4. NixOS modules and home-manager reference `/run/agenix/<name>` paths

The host age private key lives at `/var/lib/agenix/identity` on the deployed machine. The offline admin key is kept only in Bitwarden, never on machines.

`modules/secrets.nix` sets the identity path only. Machine-specific `age.secrets.*` entries live in `hosts/enterprise-d/secrets.nix` (NAS credentials, SSH key, GitHub token). Wi-Fi secret declarations live alongside the NetworkManager profiles in `roles/common/networking.nix`.

Wi-Fi credentials use environment variable substitution: `psk = "$WIFI_AGT_HOME_PASSWORD"` in `roles/common/networking.nix`, with the variable sourced from the agenix secret at activation time.

### Adding a New Wi-Fi Network

Changes needed in three places: `secrets/secrets.nix` (add recipient keys), `roles/common/networking.nix` (add both the `age.secrets."wifi/<name>".file` declaration and the NetworkManager profile), and create `secrets/wifi/<name>.age`. See README § Wi-Fi Pre-configuration for exact syntax.

### Flake Inputs

| Input | Purpose |
| --- | --- |
| `nixpkgs` (nixos-unstable) | Main package set and NixOS modules |
| `home-manager` | User environment management |
| `disko` | Declarative disk partitioning |
| `agenix` | Encrypted secrets in git |
| `lanzaboote` (v1.0.0) | Secure Boot via lanzaboote |
| `nix-flatpak` | Declarative Flatpak management |
| `nix-vscode-extensions` | Overlay that populates `pkgs.vscode-extensions.*` used in `users/thomasga/vscode.nix` |
| `pre-commit` | Lint checks in dev shell |

## Linting and Formatting Rules

All Nix files must pass:

- **alejandra** — Nix formatter (run `alejandra .` to auto-format)
- **statix** — Nix linter (no antipatterns)
- **deadnix** — no unused Nix bindings

All Markdown files must pass **markdownlint** (config in `.markdownlint.json`).

The pre-commit hook `no-plaintext-secrets` blocks staging any file that looks like a raw secret. Never create files under `secrets/` except through `nix run .#secret-edit`.

## Machine-Specific Notes

The only configured machine is `enterprise-d` (Framework laptop). See `hosts/enterprise-d/README.md` for:

- TPM2 enrollment for LUKS auto-unlock (PCR selections, enrollment commands)
- Power/hibernate behavior table (lid close, idle timings, suspend-then-hibernate)
- Post-install checklist

The current user is `thomasga` (Geoffrey Thomas). The home-manager attachment is declared directly in `flake.nix` under `home-manager.users.thomasga`.

## Working With This User

- **Timestamps:** Every response — including short follow-ups and mid-task updates — starts with `[HH:MM MDT]`. No exceptions. Always run `date +"%H:%M"` to get the real time before writing the timestamp. Never guess or carry over a time from earlier in the conversation.
- **System timezone:** MDT (UTC-6). The machine clock is `America/Edmonton`. Journal timestamps are local time. Always verify date arithmetic when computing time differences — account for the full calendar date, not just hours.
- **Communication style:** Terse and direct. No filler ("Great!", "Perfect!", "Let me now..."). Don't claim success before verifying. When something is uncertain or has tradeoffs, say so plainly rather than projecting confidence.
- **Before acting on any non-trivial task:** summarize the problem as the user stated it, explain the planned approach, and wait for confirmation before executing. This applies to investigations, fixes, and especially any state-changing operation (deleting files, overwriting content, `nixos-rebuild switch`, git commits). For state-changing operations also explain what will be lost and why this approach is correct.
- **Ask before assuming:** When intent is ambiguous or multiple valid approaches exist, ask a short targeted question rather than picking one and proceeding.
- **Read-only commands** (`lspci`, `grep`, `lsblk`, `cat`, `journalctl`, `git log`, `git diff`, `git status`, `git show`, `git branch`, etc.) are safe to run directly without asking for permission.
- **PRs:** Never merge PRs — open them, update them, and stop. Merging is the user's decision.
- **Heredoc ban:** Never use heredoc syntax (`<<'EOF'...EOF`) anywhere in shell commands — not in `git commit -m`, not in `gh pr create --body`, not anywhere. It does not work in this shell (fish). Always write multi-line strings to a temp file with the Write tool and reference it with `git commit -F /tmp/msg` or `--body-file /tmp/body`.
- **Rebuild command:** Always run `nix develop -c pre-commit run --all-files` before `sudo nixos-rebuild switch --flake .#enterprise-d` to catch option renames and formatting errors before the build fails mid-switch.
