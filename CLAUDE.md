# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

## What This Repository Does

A NixOS flake managing **four** machines declaratively — disk layout, OS, hardware, secrets, home-manager user environments, homelab services, and backup policy. Everything is committed; nothing is configured by hand after install.

| Machine | Type | Arch | Host doc |
| --- | --- | --- | --- |
| `enterprise-d` | Framework laptop, full GNOME desktop | `x86_64-linux` | `hosts/enterprise-d/README.md` |
| `reliant` | Gigabyte Brix mini PC, headless homelab server | `x86_64-linux` | `hosts/reliant/README.md` |
| `holodeck-01` | NixOS on WSL2, headless | `x86_64-linux` | `hosts/holodeck-01/README.md` |
| `excelsior` | HP EliteDesk 800 G2 Mini headless game server | `x86_64-linux` | `hosts/excelsior/README.md` |

The current user is `thomasga` (Geoffrey Thomas).

## Routing

Delegate to the specialist that owns the domain, then verify its work yourself. Specialists **cannot call each other** — for a change spanning domains, invoke them in sequence and reconcile the results.

| Request is about | Delegate to | Canonical doc |
| --- | --- | --- |
| Layer placement, new module or profile, `custom.*` options, `flake.nix`/`lib/` wiring | `architect` | `docs/architecture.md` |
| A machine — new or existing: defining, installing, enrolling, reinstalling; USB/SD/WSL media; Secure Boot; LUKS/TPM | `machine-provisioner` | `docs/provisioning.md` |
| Secrets, agenix, SSH keys, Wi-Fi credentials | `secrets-warden` | `docs/secrets.md` |
| A user — new or existing: home-manager, dotfiles, per-user GUI apps, desktop theme, adding a user | `user-provisioner` | `docs/users.md`, `docs/desktop.md` |
| Machine capability: which desktop environment, audio, idle/suspend, Podman/devcontainers, Connect IQ SDK, USB debug probes | `machine-provisioner` | `docs/workstation.md` |
| reliant reverse proxy and DNS: Traefik, AdGuard, unbound | `homelab-network` | `docs/homelab-network.md` |
| reliant appliance layer: Home Assistant, Zigbee, Z-Wave, Matter, MQTT, ADS-B | `smart-home` | `docs/smart-home.md` |
| Repo toolchain and quality gates: dev shell, `nix run .#` apps, pre-commit, flake checks, CI | `architect` | `docs/operations.md` |
| Backups: the `custom.backups` module and its doc | `architect` | `docs/backups.md` |

Rules:

- Read the owning doc before editing files in that domain.
- Any change to files in a domain updates that domain's doc in the same commit.
- **A workaround for an upstream bug — a package override, an insecure-package pin, a disabled test, anything patching around behavior that isn't this repo's own — gets a one-line bullet in the owning doc's or host README's `## Known Gotchas` section, in the same commit.** See `docs/architecture.md` § Documenting an Upstream Workaround for the format and the links-only index this feeds.
- **Everything has an owner. Owning is not the same as executing.** An agent owns a doc when it is responsible for keeping it true, independent of who runs the commands in it. Nothing is left unowned on the grounds that "the main session handles it."
- Never delegate *running* `nixos-rebuild switch`, `nix flake update`, a manual backup, or the installer. Every agent reports the command instead. That rule is about execution and changes nobody's ownership.
- Do not run `/init`. It regenerates this file wholesale and will undo the structure above. Update the owning `docs/` file instead.
- `architect` defines what a `custom.*` option *means*; each domain agent sets that option's *value* for its own instances. Nothing routes through `architect` merely because it touches `flake.nix` or a host config.
- Onboarding a machine or a user is owned end to end by its provisioner, with one hand-off each: `secrets-warden` does the age identity and SSH enrollment for a new machine, and the SSH identity secret for a new user.
- Do not merge `homelab-network` and `smart-home` back together, or fold either provisioner into `architect`. The reasoning is in the PR that introduced those boundaries.

## Documentation

| Doc | Covers |
| --- | --- |
| `docs/architecture.md` | Layers, placement rule, machine naming, directory map, full `custom.*` catalogue (canonical, all namespaces), flake inputs |
| `docs/operations.md` | Workstation setup, dev shell and `tools/`, applying and updating changes, validation commands, lint and CI |
| `docs/backups.md` | restic-to-NAS backups: how they run, enabling them on a host, status checks, limitations |
| `docs/provisioning.md` | Numbered install path for each provision type (`disko`, `sd-card`, `wsl`), including defining a new machine (Step 1) and LUKS/TPM disk encryption |
| `docs/secrets.md` | agenix model, age identities, create/rotate/rekey, secret inventory, Wi-Fi PSKs, SSH login keys vs host keys and `lib/ssh-hosts.nix` pinning |
| `docs/users.md` | User model, adding a user, dotfiles patterns, home-manager idioms |
| `docs/desktop.md` | A person's desktop: per-user GUI app opt-in, theme and wallpaper, draw.io/Obsidian |
| `docs/workstation.md` | Machine capability: `profiles/desktop/` (DE, audio, idle/suspend) and `profiles/dev/` (Podman, Connect IQ, debug probes) |
| `docs/homelab-network.md` | Traefik and DNS composition on reliant — the `custom.*` option table itself is in `docs/architecture.md` |
| `docs/smart-home.md` | Home Assistant automation rules, `extraComponents`, Zigbee/Z-Wave radio network specifics |

## Common Commands And Placement Rule

Not restated here — they live in exactly one place each, and a second copy drifts. Before any change, read:

- `docs/operations.md` for every command: dev shell, lint, `nix flake check --no-build` (never bare — it builds the aarch64 config on x86_64 and fails), per-host builds, rebuild/switch, flake updates, CI.
- `docs/secrets.md` for secret-editing and rekey commands.
- `docs/architecture.md` § Placement Rule for where new configuration belongs.

## Hard Rules

These must hold without reading any doc first.

- **Never `cd`** — not in copy-paste command blocks, not in tool-run shell commands. Use `git -C`, absolute paths, or the tool's own path flag.
- **Never use heredocs** (`<<'EOF'...EOF`) anywhere. They do not work in this shell (fish). Write multi-line strings to a temp file and use `git commit -F /tmp/msg` or `--body-file /tmp/body`.
- **Never hand-write files under `secrets/`.** Use `nix run .#secret-edit`.
- **Run `nix develop -c pre-commit run --all-files` before any `nixos-rebuild switch`**, to catch option renames and formatting errors before the build fails mid-switch.
- **One file per concern**, anywhere in the tree.
- **Home Assistant automations** use the `"automation manual"` key, never bare `"automation"`, and live one concern per file under `hosts/<host>/home-assistant/`.
- **markdownlint runs over every `.md` in the tree**, including `docs/`, `.claude/`, and host READMEs — CLAUDE.md itself included. `MD013` is the only disabled rule — so never hand-wrap markdown at a fixed column; write each paragraph as one line.

## Working With This User

### Communication

- **Timestamps:** Every response — including short follow-ups and mid-task updates — starts with `[HH:MM MDT]`. Always run `date +"%H:%M"` to get the real time before writing the timestamp. Never guess or carry over a time from earlier in the conversation.
- **System timezone:** MDT (UTC-6); the machine clock is `America/Edmonton` and journal timestamps are local time. Always verify date arithmetic against the full calendar date, not just hours.
- **Style:** Terse and direct. No filler ("Great!", "Perfect!", "Let me now..."). Don't claim success before verifying. When something is uncertain or has tradeoffs, say so plainly rather than projecting confidence. Applies to writing as much as talking — state a rule once, plainly, without padding it with justifying detail or an example.
- **Verify instead of asserting.** Don't state a fact you haven't checked — even a small incidental one — and don't answer from memory when a real check is one call away. If asked whether two PRs conflict, whether content is identical, or anything else answerable by reading the diff, file, or commit, fetch it first. Say "I'm not sure, let me verify" once rather than stating something confidently and reversing it later.
- **Confirm before acting on any non-trivial task.** Summarize the problem as stated, explain the planned approach, and wait — for state-changing operations (deleting files, overwriting content, `nixos-rebuild switch`, git commits), also explain what will be lost and why the approach is correct. When intent is ambiguous or several valid approaches exist, ask a short targeted question rather than picking one silently.
- **But don't ask permission for routine follow-through a standing instruction already covers** — e.g. updating a PR's title and description after pushing commits that change its scope. Reserve confirmation for things that are genuinely ambiguous, risky, or irreversible.
- **If I ask whether something's done and it isn't, do it — don't turn the question into a permission request.** Doubly so when it's something you should already have been doing without being asked, like squashing incremental commits before a merge.
- **Surface every decision you make on my behalf, in the message, when you make it.** Anything that forecloses something — an accepted limitation, a default picked without asking — gets said out loud at the time, even when you're confident and not asking permission. A commit message or a code comment alone is not disclosure.
- **Don't guess an external tool's config or API schema when writing code that depends on it.** Look it up — docs, source, WebFetch/WebSearch — before writing config or code whose shape you're not certain of; ask if it can't be confirmed.
- **Fix the underlying problem, don't just document it.** A comment flagging a discrepancy or stale claim isn't a fix — resolve it before landing anything. Exception: only what needs the user's own hands, credentials, or a real tradeoff call.

### Shell and commands

- **Read-only commands are safe to run without asking**: `lspci`, `grep`, `lsblk`, `cat`, `journalctl`, `git log`, `git diff`, `git status`, `git show`, `git branch`, and similar.
- **Copyable commands go in a plain markdown code block in the message body**, never inside an `AskUserQuestion` option's label or description — those aren't copyable from the option UI.
- **CI runs the real validation** (`nix flake check`, pre-commit, alejandra, statix, deadnix, per-host builds) on every push. When a sandbox has no `nix` binary, that's not a blocker to work around or apologize for — do whatever manual/structural verification is possible, then commit and push, saying once that CI will gate it rather than repeatedly flagging the gap.
- **Give commands likely to work on the first try, not clever ones.** Avoid nested command substitutions and other bash-isms when the command runs against a fish shell — that's the user's local shell, and `thomasga`'s shell on every host via home-manager — since fish's quoting and redirection rules differ. Prefer re-running a command already shown to work over building a new pipeline to extract the same information.
- **Walk manual steps one command at a time.** Give one command, wait for its output, then the next — never a batch or numbered list. Never prepend `cd` or ask what directory the user is in; assume they're already there. Don't ask the user to manually redo anything CI already validates — only give steps that need real hardware or an environment CI doesn't have.

### Git and PRs

- **Never create a new git branch without asking first and getting explicit confirmation** — including when splitting work up, consolidating existing branches, or cleaning up after yourself. Branches created without asking pile up fast and the user ends up cleaning them up.
- **Never merge PRs.** Open them, update them, and stop. Merging is the user's decision.
- **Always subscribe to PR activity without asking.** As soon as a PR exists for the session's work, subscribe to its events and follow through — respond to review comments, investigate CI failures — until it is merged or closed. Don't offer it as an option.
- **Rely on the activity subscription alone when watching a PR.** Don't also schedule a self check-in (`send_later`/routines) as a backstop.
- **Every change ships with test steps, including docs-only ones.** Put concrete commands and exact expected output in the PR description, not "verify it works", and state plainly which you actually ran versus which are for the user (hardware or a host you can't reach). A docs-only change still has a real check behind it (markdownlint, see Hard Rules), so its test plan is that CI check passing, not an empty section — manual steps are optional, and only when there's genuinely no runtime surface to exercise.
- **Flag incremental commits for squashing.** Any sequence that revises the same not-yet-merged work — a `feat` then a `fix` for a bug it introduced, or several `docs` commits refining one section — is not clean history. Nobody has seen the intermediate states, so there is nothing worth preserving; say it should be one commit rather than calling each one "individually fine".
- **Standing preferences captured mid-task land in their own commit/PR against `master`**, never bundled into whatever feature branch is checked out.

### Repo conventions

- **Favor one file per concern over lumping unrelated settings into an existing catch-all**, anywhere in the tree — `profiles/`, `modules/`, `users/`, `hosts/`. Network discovery (avahi/mDNS) belongs in `profiles/common/networking.nix`, separate from `modules/wifi.nix` (NetworkManager) and `profiles/common/base.nix` (unconditional OS settings). When adding a setting, ask whether it fits an existing file's concern or needs a new one.
- **Don't justify security or permission tradeoffs by appealing to "it's a single-user machine."** Don't propose loosening permissions (e.g. world-writable device rules) on that basis.
- **Keep the doc-to-code ratio proportionate — state a fact once, where it's owned, and point to it everywhere else.** Restating the same gotcha across a doc comment, an inline comment, and a README is the failure mode, not thoroughness. For every line of comment or documentation you add, cut two lines of existing comment or documentation in the same change — a net budget, not just a dedup pass.
