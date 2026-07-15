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
| `roles/common/` | Base OS settings, single user (`thomasga`), NetworkManager Wi-Fi profiles, network discovery (avahi/mDNS), Steam, Flatpak |
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

`modules/secrets.nix` sets the identity path only. Machine-specific `age.secrets.*` entries live in `hosts/enterprise-d/secrets.nix` (NAS credentials, SSH key, GitHub token). Wi-Fi secret declarations live alongside the NetworkManager profiles in `roles/common/wifi.nix`.

Wi-Fi credentials use environment variable substitution: `psk = "$WIFI_AGT_HOME_PASSWORD"` in `roles/common/wifi.nix`, with the variable sourced from the agenix secret at activation time.

### Adding a New Wi-Fi Network

Changes needed in three places: `secrets/secrets.nix` (add recipient keys), `roles/common/wifi.nix` (add both the `age.secrets."wifi/<name>".file` declaration and the NetworkManager profile), and create `secrets/wifi/<name>.age`. See README § Wi-Fi Pre-configuration for exact syntax.

Note: `roles/common/networking.nix` is a separate file for general network-discovery config (e.g. avahi/mDNS), kept apart from `wifi.nix` for clear separation of concerns.

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
- **Don't justify security/permission tradeoffs by appealing to "it's a single-user machine."** Don't propose loosening permissions (e.g. world-writable device rules) on that basis.
- **When reviewing commit/PR cleanliness, any sequence of commits that incrementally revise the same not-yet-merged work — a `feat` then a `fix` for a bug it introduced, or several `docs` commits each just refining the same section — is not clean or logical.** Nobody has ever seen or relied on the intermediate states, so there's no history worth preserving; flag it for squashing into one commit rather than calling each one "individually fine."
- **Copyable commands go in a plain markdown code block in the message body, never inside an `AskUserQuestion` option's label/description.** Those aren't copyable from the option UI.
- **Standing preferences captured mid-task (like the ones in this list) go in their own dedicated commit/PR against `master`, never bundled into whatever feature branch happens to be checked out at the time.** They're a process concern orthogonal to the feature being worked on; landing them separately keeps feature PR history and process-preference history each legible on their own.
- **Don't guess about repo/PR state when a real check is one call away.** If asked whether two PRs conflict, whether content is identical, or anything else answerable by actually reading the diff/file/commit, fetch it first — don't answer from memory of having written or seen it earlier in the conversation.
- **Favor one file per concern over lumping unrelated settings into an existing catch-all file, anywhere in the tree** (`roles/`, `modules/`, `users/`, etc.) — not just `roles/common/`. e.g. network-discovery config (avahi/mDNS) belongs in its own `roles/common/networking.nix`, separate from `wifi.nix` (NetworkManager/Wi-Fi) and `base.nix` (unconditional OS settings). When adding a setting, ask whether it fits an existing file's concern or needs a new one — don't default to the nearest catch-all just because it's already imported.
- **Don't assert a fact you haven't actually checked, even a small incidental one (what an icon is, whether an image is a live screenshot vs. a pasted reference, etc.).** State it as a guess, or check it, before presenting it as settled. "That's the generic GNOME icon" / "that's the real logo" said with confidence and then reversed twice in one session is worse than saying "I'm not sure, let me verify" once.
- **Don't ask permission for routine follow-through that a standing instruction already covers** (e.g. updating a PR's title/description after pushing commits that change its scope — "PRs: keep them updated" already says to do this). Asking turns a zero-judgment action into a round trip the user has to spend just to get you to do what was already asked. Reserve confirmation for things that are actually ambiguous, risky, or irreversible — not for closing the loop on your own prior work.
- **Always subscribe to PR activity without asking.** As soon as a PR exists for the session's work (opened by Claude or by the user from the session), subscribe to its events (`subscribe_pr_activity` where available) and follow through — respond to review comments, investigate CI failures — until the PR is merged or closed. Don't offer it as an option; just do it.
