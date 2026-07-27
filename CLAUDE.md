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
| Layer placement, new module or role, `custom.*` options, `flake.nix`/`lib/` wiring | `architect` | `docs/architecture.md` |
| A machine — new or existing: defining, installing, enrolling, reinstalling; USB/SD/WSL media; Secure Boot; LUKS/TPM | `machine-provisioner` | `docs/provisioning.md` |
| Secrets, agenix, SSH keys, Wi-Fi credentials | `secrets-warden` | `docs/secrets.md` |
| A user — new or existing: home-manager, dotfiles, GUI apps, desktop theme, adding a user | `user-provisioner` | `docs/users.md`, `docs/desktop.md` |
| Dev workstation: Podman/devcontainers, Connect IQ SDK, USB debug probes | `user-provisioner` | `docs/dev-workstation.md` |
| defiant reverse proxy and DNS: Traefik, AdGuard, unbound | `homelab-network` | `docs/homelab-network.md` |
| defiant appliance layer: Home Assistant, Zigbee, Z-Wave, Matter, MQTT, ADS-B | `smart-home` | `docs/smart-home.md` |
| Rebuild, update, lint, CI — **do not delegate** | handle inline | `docs/operations.md` |
| Backups: the `custom.backups` module and its doc | `architect` | `docs/backups.md` |

Rules:

- Read the owning doc before editing files in that domain.
- Any change to files in a domain updates that domain's doc in the same commit.
- Do not run `/init`. It regenerates this file wholesale and will undo the
  structure above. Update the owning `docs/` file instead.
- `architect` defines what a `custom.*` option *means*; each domain agent sets
  that option's *value* for its own instances. Nothing routes through
  `architect` merely because it touches `flake.nix` or a host config.
- Onboarding a machine or a user is owned end to end by its provisioner, with
  one hand-off each: `secrets-warden` does the age identity and SSH enrollment
  for a new machine, and the SSH identity secret for a new user.
- Do not merge `homelab-network` and `smart-home` back together, or fold either
  provisioner into `architect`. Those boundaries were set against this repo's
  commit history; the reasoning is in the PR that introduced them.

## Documentation

| Doc | Covers |
| --- | --- |
| `docs/architecture.md` | Layers, placement rule, machine naming, directory map, full `custom.*` catalogue (canonical, all namespaces), flake inputs |
| `docs/operations.md` | Workstation setup, dev shell and `tools/`, applying and updating changes, validation commands, lint and CI |
| `docs/backups.md` | restic-to-NAS backups: how they run, enabling them on a host, status checks, limitations |
| `docs/provisioning.md` | Numbered install path for each provision type (`disko`, `sd-card`, `wsl`), including defining a new machine (Step 1) and LUKS/TPM disk encryption |
| `docs/secrets.md` | agenix model, age identities, create/rotate/rekey, secret inventory, Wi-Fi PSKs, SSH login keys vs host keys and `lib/ssh-hosts.nix` pinning |
| `docs/users.md` | User model, adding a user, dotfiles patterns, home-manager idioms |
| `docs/desktop.md` | Which layer owns a graphical application, desktop theme, draw.io/Obsidian |
| `docs/dev-workstation.md` | `roles/dev/`: Podman and devcontainers, Connect IQ SDK, USB debug probe udev rules |
| `docs/homelab-network.md` | Traefik and DNS composition on defiant — the `custom.*` option table itself is in `docs/architecture.md` |
| `docs/smart-home.md` | Home Assistant automation rules, `extraComponents`, Zigbee/Z-Wave radio network specifics |

## Common Commands And Placement Rule

Not restated here — they live in exactly one place each, and a second copy
drifts. Before any change, read:

- `docs/operations.md` for every command: dev shell, lint, `nix flake check
  --no-build` (never bare — it builds the aarch64 config on x86_64 and fails),
  per-host builds, rebuild/switch, flake updates, CI.
- `docs/secrets.md` for secret-editing and rekey commands.
- `docs/architecture.md` § Placement Rule for where new configuration belongs.

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
