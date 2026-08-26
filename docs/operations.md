# Day-to-Day Operations

The human workflow for this repo: set up a workstation, apply changes to a
machine, and verify them.

Subsystems with their own docs are not covered here — [backups](backups.md),
[secrets](secrets.md), and [provisioning a new machine](provisioning.md).

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

The flake exposes five apps (defined in `lib/apps.nix`). Use these rather than
invoking `agenix` or the scripts directly:

| Command | Script | What it does |
| --- | --- | --- |
| `nix run .#secret-edit -- <file>` | `tools/secret_edit.py` | Edit or create an `.age` secret in a temporary buffer |
| `nix run .#secret-rekey` | `tools/secret_rekey.py` | Re-encrypt every tracked secret after changing recipients |
| `nix run .#install` | `tools/install.py` | Install a machine: menu, then disko or SD-card flow |
| `nix run .#provision` | `tools/provision.py` | Lower-level per-provision-type driver used by `install.py` |
| `nix run .#check-ha-entities -- <host>` | `tools/check_ha_entities.py` | Diff entity IDs referenced by declared Home Assistant automations against the host's live entity registry (over SSH) |

The remaining helpers in `tools/` are run directly:

| Script | What it does |
| --- | --- |
| `tools/enroll.py` | Enroll a machine: age identity, SSH keypair, repo wiring, rekey |
| `tools/bootstrap_ssh_key.py` | Create and encrypt an SSH keypair (used by `enroll.py`) |
| `tools/install_age_identity.py` | Install or rotate a host age identity on disk |
| `tools/check_no_plaintext_secrets.py` | Pre-commit guard against staging plaintext secrets |
| `tools/ci_changed_hosts.py` | CI only: prints the build matrix of hosts whose toplevel derivation changed |
| `tools/ha_config_check.py` | CI only: validates reliant's Home Assistant config via `hass --script check_config` |
| `tools/ci_ha_config_changed.py` | CI only: decides whether `ha_config_check.py` needs to re-run at all |
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
| `excelsior` | `nixos-rebuild switch --flake .#excelsior --target-host thomasga@excelsior.local --sudo` | Any machine with SSH and Nix |
| `reliant` | `nixos-rebuild switch --flake .#reliant --target-host thomasga@reliant.local --sudo` | Any machine with SSH and Nix |
| `enterprise-d` (remote) | `nixos-rebuild switch --flake .#enterprise-d --target-host thomasga@enterprise-d.local --sudo` | Any machine with SSH and Nix |

### Automatic updates

`profiles/common/base.nix` enables `system.autoUpgrade` for every host: it fetches
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

The package and kernel baseline tracks whichever branch the `nixpkgs` input in
`flake.nix` points at (`nixos-unstable` today). Moving to a more conservative or
more aggressive baseline is the same mechanism: change the `nixpkgs` input's
branch or revision, then run the three commands above — `nix flake update`
picks up the new target, and the lock file records it.

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

# aarch64-linux — no host currently uses this architecture. If one is added,
# it needs binfmt emulation or a native/remote aarch64 builder, e.g.:
nix build .#nixosConfigurations.<aarch64-host>.config.system.build.toplevel
nix build .#nixosConfigurations.<aarch64-host>.config.system.build.sdImage
```

`enterprise-d` sets `boot.binfmt.emulatedSystems = ["aarch64-linux"]`, so it
can cross-build an aarch64 host locally, slowly. CI sidesteps this by
building aarch64 hosts natively on an `ubuntu-24.04-arm` runner, when one
exists in the matrix.

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

`.github/workflows/ci.yml` runs on every push to `master` and every pull
request, each job posting its output as a PR comment before failing:

| Job | Command |
| --- | --- |
| `lint` | `nix develop -c pre-commit run --all-files` |
| `flake-check` | `nix flake check --no-build` |
| `changes` | `python3 tools/ci_changed_hosts.py --base <sha> --head <sha>` |
| `build` | Matrix over the hosts `changes` selected: `nix build .#nixosConfigurations.<host>.config.system.build.toplevel --no-link` |
| `ha-config-check` | `python3 tools/ha_config_check.py reliant`, scoped by `changes` (see below) |

`lint` and `flake-check` are unconditional. `build` and `ha-config-check` are
not — both depend on `changes`, which runs two derivation-diff scripts to
decide what actually needs to happen for this push or PR.

`build`'s scoping: `tools/ci_changed_hosts.py` evaluates each host's toplevel
`drvPath` at the base commit and again at the head commit, and prints a build
matrix containing only those hosts whose `drvPath` differs. A host whose
derivation is byte-identical at both commits cannot produce a different
build, so it is skipped; a docs-only change moves no host's `drvPath` and
runs zero build jobs.

Nothing about the host list is hand-maintained. The script reads it out of the
flake at each commit:

```bash
nix eval --json .#nixosConfigurations --apply builtins.attrNames
```

Registering a host in `flake.nix`'s `nixosConfigurations` is therefore the only
step needed for it to get CI coverage — there is no second list to update, and
no way to add a host that CI silently never builds. A host present at head but
not at base (a newly added machine) has nothing to compare against and is
always built.

The runner is derived the same way. For each host the script evaluates
`pkgs.system` (not `config.nixpkgs.hostPlatform.system` — that NixOS *option*
isn't populated by this repo's `mkNixosSystem`, which threads `system` through
`nixosSystem`'s top-level argument instead; `pkgs.system` is set
unconditionally regardless of how `system` was passed in) and the host's
`drvPath` in a single `nix eval`, then maps the system to the runner that
builds it natively: `x86_64-linux` to `ubuntu-latest`, `aarch64-linux` to
`ubuntu-24.04-arm`. A second aarch64 machine gets an arm64 runner
automatically; no host name appears in the mapping. A system with no mapping
falls back to `ubuntu-latest`, so it fails loudly in the build rather than
vanishing from the matrix.

The comparison is on the derivation itself, not on changed file paths, so
there is no host-to-path map that can go stale. It fails safe: if the base
commit is unreachable (new branch, force-push, shallow history) or an eval
errors out, the host is built anyway. The one hard failure is being unable to
enumerate `nixosConfigurations` at head — there is no safe list to fall back
to, so `changes` exits non-zero and CI goes red instead of building nothing.

**Caveat — over-selection from bare local-file references.** A host can show as
changed even when nothing it imports functionally changed, if anywhere in its
closure a `.nix` file hands a bare `./`/`../` path literal to a derivation as a
build input. Such a literal resolves to a subpath of the one whole-repo store
copy of `self`, so its store identity moves on every commit and drags the
host's `drvPath` with it. This costs a wasted build, never a missed one — the
optimization stays correct, just less effective. The mechanism and the fix
(`lib/local-file.nix`) are in
[docs/architecture.md § Local Files As Build Inputs](architecture.md#local-files-as-build-inputs).

The build job frees disk space on the runner before building, since a full
desktop closure can exhaust the default runner disk.

**`ha-config-check`'s scoping** is two layers, both keyed to `reliant` (the
only host with Home Assistant enabled — there is no second host yet to
justify generalizing this):

1. If `reliant` isn't in the `changes` matrix above, its toplevel didn't
   change at all, so nothing about its Home Assistant config could have
   either — the check is skipped with no further evaluation
   (`ha-reliant-changed=false`).
2. If it is, `tools/ci_ha_config_changed.py` diffs the drvPaths of the three
   flake packages `tools/ha_config_check.py` actually builds
   (`packages.<system>.ha-config-reliant`, the rendered automation config;
   `ha-check-hass` and `ha-check-colorlog`, the validator itself) between
   base and head. Most reliant changes — Traefik, Bambuddy, Z-Wave, etc. —
   move reliant's toplevel without touching any of these three, and are
   correctly skipped. A nixpkgs bump that changes the `home-assistant`
   package still trips this even when no automation file moved, since
   `ha-check-hass`'s drvPath moves too.

Both scripts fail safe: any checkout/eval problem is treated as "changed"
rather than risking a skipped validation.

### Pull request template

`.github/pull_request_template.md` pre-fills the description of every PR opened
against this repo. It is a checklist, not prose, and exists so no PR ships
without a test plan someone else can re-run.

It asks for two things:

1. **Summary** — why the change is needed and which hosts it affects. Not
   what changed — the diff shows that.
2. **Test plan** — one ordered checklist of concrete copyable commands in
   fenced code blocks with the expected output noted. Tick a box only if you
   ran that command and saw that output; leave unchecked whatever needs
   hardware, an unreachable host, or a command nobody automates
   (`nixos-rebuild switch`, `nix flake update`, a manual backup, the
   installer), and say in the item who runs it. Lint and format is never
   skippable — `pre-commit` runs markdownlint over every `.md` file, so even a
   docs-only PR runs it. Only the flake-evaluation and host-build steps are
   N/A when no `.nix` file changed.

The default author steps mirror the [validation commands](#validation-commands)
above and the CI jobs in the table before this section; keep the three in step
when any of them changes.
