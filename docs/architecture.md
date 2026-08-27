# Repository Architecture

How this repo is layered, where a given piece of configuration belongs, and what
the shared vocabulary (`custom.*`, `mkNixosSystem`) means.

## Layers

The configuration is a DAG of imports. Deciding which layer to edit is the main
architectural decision. Every arrow below is an *import*, not containment —
`modules/`, `profiles/`, and `users/` are all top-level directories alongside
`hosts/`, which is why each node is written as a full path from the repo root:

```text
flake.nix
  └─> hosts/<host>/default.nix
        ├─> hosts/<host>/configuration.nix
        │     ├─> hosts/<host>/{hardware,disko,power,secrets}.nix  # machine-specific
        │     ├─> profiles/common  (+ desktop, dev)                # set config; per host, by name; active on import
        │     └─> modules/                                         # declare custom.* options; every host imports all; inert until enabled
        └─> hosts/<host>/home/<user>.nix                           # via home-manager.users.<user>.imports
              └─> users/<user>/{desktop,headless}.nix              # personal: dotfiles, shell, apps
                    └─> users/common/                              # opt-in shared user modules
```

The repo is split by responsibility:

- `hosts/<machine>/` owns machine-specific hardware, power, and disk layout.
- `profiles/` owns preset bundles a host opts into by name — the baseline OS
  settings, network discovery, the agenix identity path, the desktop baseline,
  the dev toolchain. Profiles set config; they declare no options.
- `modules/` owns the `custom.*` feature modules — users, Wi-Fi, backups,
  btrfs, secure boot. Modules declare options; every host imports all of them
  via `modules/default.nix`, and each contributes nothing until its option is
  set.
- `users/<name>/` owns personal applications, dotfiles, shell behavior, and
  workflow tooling through home-manager.
- `secrets/` owns agenix-encrypted material that is safe to commit.

**Module or profile? One mechanical test: does the file declare `options`?**

| | Declares `options` | Imported | Effect |
| --- | --- | --- | --- |
| `modules/` | yes | by every host, whole | none until its option is set |
| `profiles/` | no | per host, by name | immediate |

There is deliberately no `profiles/default.nix` aggregating every profile the
way `modules/default.nix` aggregates every module. Importing all modules is
safe because each module contributes nothing to a host that has not set its
options — enforced by the `modules-inert` flake check
(`lib/module-inertness.nix`), which applies every module to a probe host with
no `custom.*` set and fails any whose `config` isn't inert. Importing all
profiles would not be safe: they apply config on import, so an aggregator would
apply every profile to whichever host imported it, and adding a profile would
change that host without anyone choosing to. "Profile" is NixOS's own term for
a preset bundle of settings; see `nixpkgs/nixos/modules/profiles/`. "Role" is
not a NixOS concept and this repo no longer uses it.

## Placement Rule

This is the canonical statement. Every other doc links here rather than
restating it.

- If it affects machine operation, put it in the system layer:
  `hosts/<machine>/` for machine-specific behavior, `profiles/` for a preset a
  host opts into by name, or `modules/` for a reusable feature behind a
  `custom.*` option.
- If it affects a person's workflow, put it in that user's home-manager config
  under `users/<name>/`, in a profile such as `users/<name>/desktop.nix`
  (full GUI) or `users/<name>/headless.nix` (CLI-only).
- If several users may want it, create a reusable opt-in user module under
  `users/common/` and import it from the relevant profile instead of forcing it
  globally.

## One File Per Concern

Favor a new file over adding an unrelated setting to an existing catch-all file,
anywhere in the tree — `profiles/`, `modules/`, `users/`, `hosts/`.

The worked example is networking. Three separate files, three separate concerns:

| File | Concern |
| --- | --- |
| `profiles/common/base.nix` | Unconditional OS settings every host gets |
| `modules/wifi.nix` | NetworkManager profiles and Wi-Fi credentials, behind `custom.wifi.enable` |
| `profiles/common/networking.nix` | Network discovery (avahi/mDNS) |

When adding a setting, ask whether it fits an existing file's concern or needs a
new one. Do not default to the nearest catch-all just because it is already
imported.

## The Aggregator Pattern

Adding a new file is always three steps, in this order, everywhere in the tree:

1. Create the file — `modules/<feature>.nix`, `profiles/common/<concern>.nix`,
   `users/common/<app>.nix`.
2. Add one import line to the sibling `default.nix`.
3. Opt in where it applies — `custom.<feature>.enable = true;` in a host
   configuration (for a module), or an import in a host or user profile such as
   `hosts/<host>/configuration.nix` or `users/thomasga/desktop.nix` (for a
   profile — profiles have no aggregator; see above).

**Step 2 is the one that fails silently.** A `.nix` file no `default.nix`
imports is never evaluated, so it raises no error — it simply does nothing.
`nix flake check` never sees it, and `deadnix` reports unused *bindings*, not
unimported *files*. `profiles/common/ssh-known-hosts.nix` (then
`modules/ssh-known-hosts.nix`) sat unimported from the commit that added it,
which meant SSH host-key pinning quietly did nothing.

`tools/check_orphan_nix.py` now enforces step 2. It runs as a pre-commit hook
and as a flake check, walking import edges out from `flake.nix` and failing on
anything it cannot reach. If a file is deliberately not imported, add it to
`ALLOWED_ORPHANS` in that script with a comment explaining why.

`tools/test_check_orphan_nix.py` is that checker's own negative test — a check
that cannot fail is worth nothing. It runs the checker against small fixture
trees under a tempdir rather than this repo, so it cannot leave a stray file
staged here, and it also runs as both a pre-commit hook and a flake check
(`orphanNixSelfTest`) rather than something run once by hand and forgotten.

This check covers reachability, not whether a module's config is gated —
`lib/module-inertness.nix` (§ Layers, above) is what catches an ungated
module.

## Local Files As Build Inputs

A `.nix` file in this repo that references a local asset — an avatar, a
wallpaper, a static udev rule file — must not hand the bare path literal
straight to a derivation. Use `lib/local-file.nix`:

```nix
localFile = import ../../lib/local-file.nix;
# ...
".face".source = localFile {path = ./files/face.png;};
```

### Why

Nix copies this flake's whole local source (`self`) into the store as **one**
content-addressed unit before evaluation begins. A bare relative path literal
written inside that tree — `./files/face.png` — resolves to a *subpath* of that
single copy, not to an independently-hashed copy of just that file. So the
moment the literal is coerced to a string or store path, the resulting value
carries the whole-repo hash:

- `toString ./file`
- `${./file}` interpolated into a derivation builder script
- `.source = ./file;` in home-manager or `environment.etc`

Every one of those embeds a value that changes whenever **any** tracked file
anywhere in the repo changes, including files with no logical relationship to
it. `builtins.path` instead NAR-hashes the given path's own content,
independent of where it sits during evaluation, which is all
`lib/local-file.nix` does.

This is not cosmetic. It silently defeats `tools/ci_changed_hosts.py`, which
decides what CI builds by comparing each host's toplevel `drvPath` across two
commits: a host whose closure embeds one of these references shows as changed
on a commit that touched only some other host. That was empirically confirmed
with `nix-diff`; `enterprise-d` was rebuilt by a PR that touched only another
host's `hosts/*`, via `users/thomasga/account.nix`'s `avatar`.

One shape that looks identical but is **not** affected:
`age.secrets.<name>.file = ../../secrets/x.age;`. In the same real CI run,
`holodeck-01` and `excelsior` — which each carry such references — both
reported `drvPath unchanged`. Leave them alone; the reason has not been pinned
down, and reshaping what agenix receives as `file` risks breaking decryption
for no measured gain.

### Decision rule

Two branches, and the first is almost always the right one:

| Situation | Do this |
| --- | --- |
| The content is used only by this repo — avatars, wallpapers, static rule files. The common case. | `lib/local-file.nix` |
| The content is genuinely shared with a project outside this repo | A real separate repo, pinned as a `flake = false` input, `dotfiles`-style |

The second branch is rare and is **not** a workaround for the hashing problem
above — `lib/local-file.nix` already solves that, in-tree, with no new
repository to maintain. The only thing that justifies a separate input is an
actual external consumer. The existing precedent is the `dotfiles` input,
whose fish/git configuration is consumed both here and by a separate
devcontainer-features project. Do not spin up a repository every time an asset
needs to reach a derivation.

## Machine Naming

Machine names are drawn from ships, stations, and notable locations in Star
Trek, Star Wars, and Battlestar Galactica:

- Prefer single-word names; use multiple words only when the canonical name
  genuinely requires it
- Hyphenate multi-word names (e.g. `enterprise-d`, because the D is part of the
  official ship designation NCC-1701-D)
- No character names
- Physical machines: named after specific vessels or stations (e.g.
  `enterprise-d`, `galactica`, `reliant`)
- WSL instances: `holodeck-<NN>` (e.g. `holodeck-01`, `holodeck-02`)

The machines currently in this repo are listed in the [root README](../README.md#machines).

## Directory Map

| Path | Purpose |
| --- | --- |
| `flake.nix` | Single entry point: inputs, dev shell, checks, apps, `nixosConfigurations`, `homeConfigurations` |
| `hosts/enterprise-d/` | Framework laptop: hardware scan, disko disk layout, power/hibernate policy |
| `hosts/holodeck-01/` | NixOS-WSL instance |
| `hosts/excelsior/` | Headless x86_64 game server: DCS World dedicated server + DCS-SRS, second independent DNS instance |
| `hosts/reliant/` | Gigabyte Brix mini PC: homelab server — DNS, Traefik, Home Assistant, the radio/appliance stack (Zigbee, Z-Wave, Matter, MQTT, ADS-B), and Bambuddy 3D-printer management |
| `profiles/common/` | Baseline every host gets: nix settings/GC, `system.autoUpgrade`, timezone/locale, kernel, fonts; plus network discovery (avahi/mDNS), the agenix identity path, SSH known-hosts rendering |
| `profiles/desktop/` | Desktop environment baseline, audio (pipewire), power/idle policy |
| `profiles/dev/` | Dev tooling: GitHub CLI, container runtime, network tools |
| `modules/` | `custom.*` feature modules: users, Wi-Fi, backups, btrfs, snapper, secure boot, TPM-LUKS, Steam, Flatpak, homelab services (see the `custom.*` catalogue below) |
| `modules/udev-rules/` | Verbatim upstream udev rule files loaded via `services.udev.packages` |
| `users/thomasga/` | Git, SSH, fish shell, GNOME dconf, VS Code, wallpaper, per-machine profiles |
| `users/common/` | Shared opt-in user modules: CLI tools, GUI apps, appearance |
| `lib/` | `apps.nix`, `checks.nix`, `module-inertness.nix` (the `modules-inert` check), `devshell.nix`, `local-file.nix` (see [§ Local Files As Build Inputs](#local-files-as-build-inputs)), `nas.nix`, `nixos-system.nix`, `ssh-hosts.nix`, `traefik-route.nix` |
| `secrets/` | agenix `.age` files (safe to commit) plus `secrets/secrets.nix` (recipient declarations) |
| `pkgs/` | Custom package builds: `search-light`, `connect-iq-sdk-manager-cli` (`framework-control` moved upstream to nixpkgs), `pywiim` + `home-assistant-wiim` (see [docs/smart-home.md § Wiim](smart-home.md#wiim-community-integration-not-core-linkplay)), `bambuddy` (npm-built frontend + Python backend, consumed by `modules/bambuddy.nix`) |
| `tools/` | Python provisioning and secret helpers (plus one shell script, `hibernate-test-report.sh`) |
| `docs/` | This documentation tree |

## Documenting an Upstream Workaround

When the config deviates from the obvious shape because of an upstream bug, the
deviation gets a one-line bullet in the `## Known Gotchas` section of the owning
host README (or, for a cross-host concern, the owning domain doc). The bullet
names the option or setting and states the consequence in one sentence, then
links to the fuller explanation — the relevant `docs/*.md` subsection and/or the
code comment that cites the actual upstream issue. The issue link itself lives
in that code comment, next to the line it justifies, so it is visible to anyone
reading the code without the doc.

## Known Workarounds

Index of every doc that carries a `## Known Gotchas` section. Links only, by
design: the text stays in one place and this list exists so the set of active
workarounds can be found and revisited without re-deriving where they live.

- [`hosts/reliant/README.md` § Known Gotchas](../hosts/reliant/README.md#known-gotchas)
- [`hosts/excelsior/README.md` § Known Gotchas](../hosts/excelsior/README.md#known-gotchas)
- [`hosts/enterprise-d/README.md` § Known Gotchas](../hosts/enterprise-d/README.md#known-gotchas)
- [`docs/desktop.md` § Known Gotchas](desktop.md#known-gotchas)
- [`docs/secrets.md` § Known Gotchas](secrets.md#known-gotchas)

## Custom Options

Modules expose behavior through `custom.*` options rather than direct NixOS
options, so a host configuration reads as a list of intents.

Every `custom.*` option is declared under `modules/` — that is the module/profile
test from § Layers applied consistently, with no exceptions today.

### System policy

| Option | Declared in | What it does |
| --- | --- | --- |
| `custom.isLaptop` | `modules/is-laptop.nix` | Gates AC-power-sensitive maintenance jobs (NAS backups, auto-upgrade, Flatpak auto-update) |
| `custom.nix.gc.keepGenerations` | `modules/nix-gc.nix` | How many system and home-manager profile generations the weekly nix-gc run keeps (default `10`); lower it on hosts with little disk headroom, such as an SD-card-booted Pi |
| `custom.users` | `modules/users.nix` | Declares user accounts, groups, and SSH authorized keys |
| `custom.backups` | `modules/backups.nix` | Per-entry restic backups to the NAS over SMB or NFS |
| `custom.wifi.enable` | `modules/wifi.nix` | NetworkManager `ensureProfiles` Wi-Fi profiles |
| `custom.networkDrives` | `modules/network-drives.nix` | Per-user SMB share as a lazy, keyring-free CIFS `x-systemd.automount`; adds GTK bookmarks and Dolphin Places entries |
| `custom.ssh.identitySecret` | `users/common/` | Names the agenix secret holding a user's SSH login key |

### Boot, disk, and firmware

| Option | What it does |
| --- | --- |
| `custom.btrfs.enable` | btrfs compression on the root filesystem |
| `custom.snapper.enable` | snapper btrfs snapshot schedules |
| `custom.secureBoot.enable` | Secure Boot via lanzaboote |
| `custom.tpmLuks.enable` | TPM2-sealed LUKS root unlock |
| `custom.fwupd.enable` | fwupd daemon for LVFS firmware updates |
| `custom.framework.enable` | `framework-tool` CLI plus fingerprint-reader support (fprintd, PAM for login/sudo/GDM); defaults `services.framework-control.enable` on (`mkDefault`, overridable) |

### Desktop and workstation

| Option | What it does |
| --- | --- |
| `custom.desktop.environment` | Declared in `modules/desktop.nix`. Selects the desktop environment / Wayland compositor (`"gnome"` or `"hyprland"`, default `"gnome"`). The DE's system profile (`profiles/desktop/<de>.nix`) and its home-manager config (`users/<name>/<de>.nix`, gated on `osConfig.custom.desktop.environment`) both `lib.mkIf` on this value, so the tree can carry several desktops with only the selected one applied. Each DE owns its own greeter (GNOME and Hyprland both use GDM, configured in their own profile file); DE-independent layers — audio, power/idle, printing (`profiles/desktop/printing.nix`), and the DE-neutral home bits in `users/<name>/desktop-common.nix` — are always present. |
| `custom.appearance.darkMode` | System-wide dark mode (home-manager, `users/common/appearance.nix`) |
| `custom.cli.shell` | Selects which shell the user CLI modules activate |
| `custom.gaming.enable` | Steam |
| `custom.flatpak.enable` | Declarative Flatpak plus a weekly update timer |
| `custom.vr.enable` | VR runtime support |
| `custom.ai.claude.enable` / `custom.ai.copilot.enable` | Claude / GitHub Copilot integration in VS Code |
| `custom.debugProbes.enable` | udev rules for USB JTAG/SWD probes — see [docs/workstation.md](workstation.md#usb-debug-probes-udev) |
| `custom.binCompat.enable` | Symlinks `/bin/bash` for tools whose shebang expects it |

### Homelab services

`custom.traefik` and the appliance modules (`home-assistant`, `mqtt`, `matter`,
`zigbee`, `zwave`, `adsb`, `bambuddy`) are enabled only on `reliant`. `custom.dns` runs on
**both** `reliant` and `excelsior` as two independent instances — AdGuard Home
has no native clustering, so redundancy means two separate resolvers, not
shared config. See [docs/homelab-network.md](homelab-network.md).

| Option | What it does |
| --- | --- |
| `custom.dns` | unbound recursive resolver plus AdGuard Home, with split-horizon records; `adminSubdomain` names its own Traefik route when two instances share one domain |
| `custom.traefik` | Reverse proxy with ACME wildcard certificates via a DNS-01 provider |
| `custom.home-assistant` | Home Assistant service, `extraComponents`, HTTP/proxy wiring |
| `custom.mqtt` | Mosquitto broker |
| `custom.matter` | python-matter-server |
| `custom.zigbee` | Zigbee2MQTT |
| `custom.zwave` | Z-Wave JS server |
| `custom.adsb` | dump1090 ADS-B receiver |
| `custom.bambuddy` | Bambuddy Bambu Lab printer management (`pkgs/bambuddy.nix`) as a native systemd service; `virtualPrinter.openFirewall` opens the LAN printer-protocol ports, which collide with AdGuard Home on 3000 (asserted) |
| `custom.bambuddy.slicerSidecar` | Server-side slicing sidecar for Bambuddy — the prebuilt amd64-only `orca-slicer-api` OCI image under podman, loopback-only, on by default with the parent; `bambuStudio` is a second, off-by-default sidecar |

### Game server

Enabled on `excelsior`. Not a "homelab service" in the Traefik/appliance sense
above — a standalone game server with its own two-container split.

| Option | What it does |
| --- | --- |
| `custom.dcsServer` | DCS World dedicated server (Aterfax OCI image under podman) |
| `custom.dcsServer.srs` | DCS-SRS voice server — a separate `jaycadi/dcs-srs-server` container, not bundled with the DCS image |

## Flake Inputs

| Input | Purpose |
| --- | --- |
| `nixpkgs` (nixos-unstable) | Main package set and NixOS modules |
| `home-manager` | User environment management |
| `disko` | Declarative disk partitioning |
| `agenix` | Encrypted secrets in git |
| `lanzaboote` (v1.0.0) | Secure Boot |
| `nixos-wsl` | NixOS on WSL2 (`holodeck-01`) |
| `nix-flatpak` | Declarative Flatpak management |
| `nix-vscode-extensions` | Overlay populating `pkgs.vscode-extensions.*` |
| `pre-commit` | Lint checks in the dev shell |
| `dotfiles` | Non-flake pin of the shared fish/git dotfiles repo — see [docs/users.md](users.md#pattern-1-shared-look-and-feel-via-dotfiles) |

## Where home-manager Attaches

`lib/nixos-system.nix` defines `mkNixosSystem`, which wires in `home-manager`,
`agenix`, `allowUnfree`, and shared settings for every host.

The per-user attachment lives in `hosts/<machine>/default.nix`:

```nix
home-manager.users.thomasga.imports = [./home/thomasga.nix];
```

`flake.nix` itself carries only cross-cutting overrides (for example
`enterprise-d`'s Firefox `configPath`). Do not add per-user module imports there.

Each user–machine pair also gets a standalone `homeConfigurations."<user>@<machine>"`
output, built by `mkHomeConfig` in `flake.nix`, so a user can apply their own
environment without `sudo`. See
[docs/operations.md](operations.md#user-environment-updates-self-serve-no-sudo).

The procedure to bring a new machine into existence — the files to create and
the `mkNixosSystem` registration — is
[docs/provisioning.md § Step 1](provisioning.md#step-1--define-the-machine-in-the-repo),
not here. This doc is reference, not a runbook.

The current package/kernel baseline is set by the `nixpkgs` input in
`flake.nix`. Changing it — including moving to a different branch — uses the
same mechanism as a routine flake update; see
[docs/operations.md § Monthly flake input update](operations.md#monthly-flake-input-update).
