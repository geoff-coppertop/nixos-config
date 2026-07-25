# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

## What This Repository Does

A NixOS flake managing **three** machines declaratively — disk layout, OS,
hardware, secrets, home-manager user environments, homelab services, and backup
policy. Everything is committed; nothing is configured by hand after install.

| Machine | Type | Arch | Host doc |
| --- | --- | --- | --- |
| `enterprise-d` | Framework laptop, full GNOME desktop | `x86_64-linux` | `hosts/enterprise-d/README.md` |
| `defiant` | Raspberry Pi 4 headless homelab server | `aarch64-linux` | `hosts/defiant/README.md` |
| `holodeck-01` | NixOS on WSL2, headless | `x86_64-linux` | `hosts/holodeck-01/README.md` |

The current user is `thomasga` (Geoffrey Thomas).

## Routing

Delegate to the specialist that owns the domain, then verify its work yourself.
Specialists **cannot call each other** — for a change spanning domains, invoke
them in sequence and reconcile the results.

| Request is about | Delegate to | Canonical doc |
| --- | --- | --- |
| Layer placement, new module or role, `custom.*` options, `flake.nix`/`lib/` wiring | `nix-architect` | `docs/architecture.md` |
| Installing, enrolling, or reinstalling a machine; USB/SD/WSL media; Secure Boot | `nix-provisioner` | `docs/provisioning.md` |
| Secrets, agenix, LUKS/TPM, SSH keys, Wi-Fi credentials | `secrets-warden` | `docs/secrets.md`, `docs/ssh.md` |
| home-manager, dotfiles, GUI apps, GNOME, adding a user | `home-env` | `docs/users.md`, `docs/desktop.md` |
| defiant services: Home Assistant, Zigbee, Z-Wave, Matter, MQTT, DNS, Traefik, ADS-B | `homelab-ops` | `docs/homelab.md` |
| Rebuild, update, backups, lint, CI — **do not delegate** | handle inline | `docs/operations.md` |

Rules:

- Read the owning doc before editing files in that domain.
- Any change to files in a domain updates that domain's doc in the same commit.
- Do not run `/init`. It regenerates this file wholesale and will undo the
  structure above. Update the owning `docs/` file instead.

## Documentation

| Doc | Covers |
| --- | --- |
| `docs/architecture.md` | Layers, placement rule, machine naming, directory map, full `custom.*` catalogue, flake inputs, defining a new machine |
| `docs/operations.md` | Workstation setup, dev shell and `tools/`, update policy, backups, validation commands, lint and CI |
| `docs/provisioning.md` | Numbered install path for each provision type (`disko`, `sd-card`, `wsl`) |
| `docs/secrets.md` | agenix model, age identities, create/rotate/rekey, secret inventory, Wi-Fi PSKs, LUKS and TPM |
| `docs/ssh.md` | Login keys vs host keys, `enroll.py`, `lib/ssh-hosts.nix` schema and pinning |
| `docs/users.md` | User model, adding a user, dotfiles patterns, home-manager idioms |
| `docs/desktop.md` | Application ownership, GNOME theme, draw.io/Obsidian, Connect IQ, USB debug probes |
| `docs/homelab.md` | Service module map, Traefik and DNS composition, Home Assistant automation rules |

## Common Commands

All commands assume Nix with flakes enabled and the shell already at the repo
root.

```bash
nix develop                                  # dev shell (required for secret editing and lint tools)
nix develop -c pre-commit run --all-files    # all linters and format checks
nix flake check --no-build                   # evaluate every config, skip derivations
```

```bash
# Build validation — x86_64 hosts build natively
nix build .#nixosConfigurations.enterprise-d.config.system.build.toplevel
nix build .#nixosConfigurations.holodeck-01.config.system.build.toplevel

# aarch64 needs binfmt emulation or a native/remote builder (slow locally).
# CI sidesteps this by building defiant on an ubuntu-24.04-arm runner.
nix build .#nixosConfigurations.defiant.config.system.build.toplevel
nix build .#nixosConfigurations.defiant.config.system.build.sdImage
```

Use `--no-build` on `nix flake check`, never the bare form: the bare form tries
to build all `nixosConfigurations` including the aarch64 one, which fails with a
platform mismatch on x86_64.

```bash
# Apply, per host
sudo nixos-rebuild switch --flake .#enterprise-d
sudo nixos-rebuild switch --flake .#holodeck-01           # inside the WSL distro
nixos-rebuild switch --flake .#defiant \
  --target-host thomasga@defiant --use-remote-sudo

# Monthly flake input update
nix flake update
sudo nixos-rebuild dry-activate --flake .#enterprise-d

# Secrets
EDITOR=nano nix run .#secret-edit -- secrets/thomasga/restic-password.age
nix run .#secret-rekey
nix eval .#nixosConfigurations.enterprise-d.config.age.identityPaths --json
```

## Placement Rule

- Machine behavior → `hosts/<machine>/` (machine-specific), `roles/` (shared
  policy), or `modules/` (reusable feature).
- Personal workflow → `users/<name>/` (home-manager).
- Shared optional user feature → `users/common/`, imported by choice per user.

Full version, with the layer diagram and the `custom.*` catalogue, in
`docs/architecture.md`.

## Hard Rules

These must hold without reading any doc first.

- **Never `cd`** — not in copy-paste command blocks, not in tool-run shell
  commands. Use `git -C`, absolute paths, or the tool's own path flag.
- **Never use heredocs** (`<<'EOF'...EOF`) anywhere. They do not work in this
  shell (fish). Write multi-line strings to a temp file and use `git commit -F
  /tmp/msg` or `--body-file /tmp/body`.
- **Never hand-write files under `secrets/`.** Use `nix run .#secret-edit`.
- **Run `nix develop -c pre-commit run --all-files` before any
  `nixos-rebuild switch`**, to catch option renames and formatting errors before
  the build fails mid-switch.
- **One file per concern**, anywhere in the tree.
- **Home Assistant automations** use the `"automation manual"` key, never bare
  `"automation"`, and live one concern per file under
  `hosts/<host>/home-assistant/`.
- **markdownlint runs over every `.md` in the tree**, including `docs/`,
  `.claude/`, and host READMEs. `MD013` is the only disabled rule.

## Working With This User

### Communication

- **Timestamps:** Every response — including short follow-ups and mid-task
  updates — starts with `[HH:MM MDT]`. No exceptions. Always run `date +"%H:%M"`
  to get the real time before writing the timestamp. Never guess or carry over a
  time from earlier in the conversation.
- **System timezone:** MDT (UTC-6); the machine clock is `America/Edmonton` and
  journal timestamps are local time. Always verify date arithmetic against the
  full calendar date, not just hours.
- **Style:** Terse and direct. No filler ("Great!", "Perfect!", "Let me
  now..."). Don't claim success before verifying. When something is uncertain or
  has tradeoffs, say so plainly rather than projecting confidence.
- **Verify instead of asserting.** Don't state a fact you haven't checked — even
  a small incidental one — and don't answer from memory when a real check is one
  call away. If asked whether two PRs conflict, whether content is identical, or
  anything else answerable by reading the diff, file, or commit, fetch it first.
  Say "I'm not sure, let me verify" once rather than stating something
  confidently and reversing it later.
- **Confirm before acting on any non-trivial task.** Summarize the problem as
  stated, explain the planned approach, and wait. This applies to
  investigations, fixes, and especially state-changing operations (deleting
  files, overwriting content, `nixos-rebuild switch`, git commits) — for those,
  also explain what will be lost and why the approach is correct. When intent is
  ambiguous or several valid approaches exist, ask a short targeted question
  rather than picking one silently.
- **But don't ask permission for routine follow-through a standing instruction
  already covers** — e.g. updating a PR's title and description after pushing
  commits that change its scope. Reserve confirmation for things that are
  genuinely ambiguous, risky, or irreversible.

### Shell and commands

- **Read-only commands are safe to run without asking**: `lspci`, `grep`,
  `lsblk`, `cat`, `journalctl`, `git log`, `git diff`, `git status`, `git show`,
  `git branch`, and similar.
- **Copyable commands go in a plain markdown code block in the message body**,
  never inside an `AskUserQuestion` option's label or description — those aren't
  copyable from the option UI.

### Git and PRs

- **Never merge PRs.** Open them, update them, and stop. Merging is the user's
  decision.
- **Always subscribe to PR activity without asking.** As soon as a PR exists for
  the session's work, subscribe to its events and follow through — respond to
  review comments, investigate CI failures — until it is merged or closed. Don't
  offer it as an option.
- **Rely on the activity subscription alone when watching a PR.** Don't also
  schedule a self check-in (`send_later`/routines) as a backstop.
- **Every change ships with test steps unless it's docs-only.** Put concrete
  commands and exact expected output in the PR description, not "verify it
  works". State plainly which steps you actually ran and which are for the user
  (anything needing hardware or a host you can't reach). The sole exception is a
  docs-only change with no runtime surface.
- **Flag incremental commits for squashing.** Any sequence that revises the same
  not-yet-merged work — a `feat` then a `fix` for a bug it introduced, or several
  `docs` commits refining one section — is not clean history. Nobody has seen the
  intermediate states, so there is nothing worth preserving; say it should be one
  commit rather than calling each one "individually fine".
- **Standing preferences captured mid-task land in their own commit/PR against
  `master`**, never bundled into whatever feature branch is checked out. They're
  a process concern orthogonal to the feature.

### Repo conventions

- **Favor one file per concern over lumping unrelated settings into an existing
  catch-all**, anywhere in the tree — `roles/`, `modules/`, `users/`, `hosts/`.
  Network discovery (avahi/mDNS) belongs in `roles/common/networking.nix`,
  separate from `wifi.nix` (NetworkManager) and `base.nix` (unconditional OS
  settings). When adding a setting, ask whether it fits an existing file's
  concern or needs a new one.
- **Don't justify security or permission tradeoffs by appealing to "it's a
  single-user machine."** Don't propose loosening permissions (e.g.
  world-writable device rules) on that basis.
