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

## Machine Naming

Machine names are drawn from ships, stations, and notable locations in Star
Trek, Star Wars, and Battlestar Galactica:

- Prefer single-word names; use multiple words only when the canonical name
  genuinely requires it
- Hyphenate multi-word names (e.g. `enterprise-d`, because the D is part of the
  official ship designation NCC-1701-D)
- No character names
- Physical machines: named after specific vessels or stations (e.g.
  `enterprise-d`, `galactica`, `defiant`)
- WSL instances: `holodeck-<NN>` (e.g. `holodeck-01`, `holodeck-02`)

The machines currently in this repo are listed in the [root README](../README.md#machines).

## Directory Map

| Path | Purpose |
| --- | --- |
| `flake.nix` | Single entry point: inputs, dev shell, checks, apps, `nixosConfigurations`, `homeConfigurations` |
| `hosts/enterprise-d/` | Framework laptop: hardware scan, disko disk layout, power/hibernate policy |
| `hosts/defiant/` | Raspberry Pi 4 homelab server: SD image, homelab service config, Home Assistant automations |
| `hosts/holodeck-01/` | NixOS-WSL instance |
| `profiles/common/` | Baseline every host gets: nix settings/GC, `system.autoUpgrade`, timezone/locale, kernel, fonts; plus network discovery (avahi/mDNS), the agenix identity path, SSH known-hosts rendering |
| `profiles/desktop/` | Desktop environment baseline, audio (pipewire), power/idle policy |
| `profiles/dev/` | Dev tooling: GitHub CLI, container runtime, network tools |
| `modules/` | `custom.*` feature modules: users, Wi-Fi, backups, btrfs, snapper, secure boot, TPM-LUKS, Steam, Flatpak, homelab services (see the `custom.*` catalogue below) |
| `modules/udev-rules/` | Verbatim upstream udev rule files loaded via `services.udev.packages` |
| `users/thomasga/` | Git, SSH, fish shell, GNOME dconf, VS Code, wallpaper, per-machine profiles |
| `users/common/` | Shared opt-in user modules: CLI tools, GUI apps, appearance |
| `lib/` | `apps.nix`, `checks.nix`, `module-inertness.nix` (the `modules-inert` check), `devshell.nix`, `nas.nix`, `nixos-system.nix`, `ssh-hosts.nix`, `traefik-route.nix` |
| `secrets/` | agenix `.age` files (safe to commit) plus `secrets/secrets.nix` (recipient declarations) |
| `pkgs/` | Custom package builds: `search-light`, `connect-iq-sdk-manager-cli` (`framework-control` moved upstream to nixpkgs) |
| `tools/` | Python provisioning and secret helpers (plus one shell script, `hibernate-test-report.sh`) |
| `docs/` | This documentation tree |

## Custom Options

Modules expose behavior through `custom.*` options rather than direct NixOS
options, so a host configuration reads as a list of intents.

Every `custom.*` option is declared under `modules/` — that is the module/profile
test from § Layers applied consistently, with no exceptions today.

### System policy

| Option | Declared in | What it does |
| --- | --- | --- |
| `custom.isLaptop` | `modules/is-laptop.nix` | Gates AC-power-sensitive maintenance jobs (NAS backups, auto-upgrade, Flatpak auto-update) |
| `custom.users` | `modules/users.nix` | Declares user accounts, groups, and SSH authorized keys |
| `custom.backups` | `modules/backups.nix` | Per-entry restic backups to the NAS over SMB or NFS |
| `custom.wifi.enable` | `modules/wifi.nix` | NetworkManager `ensureProfiles` Wi-Fi profiles |
| `custom.networkDrives` | `modules/network-drives.nix` | Auto-mount SMB shares at graphical login |
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
| `custom.appearance.darkMode` | System-wide dark mode (home-manager, `users/common/appearance.nix`) |
| `custom.cli.shell` | Selects which shell the user CLI modules activate |
| `custom.gaming.enable` | Steam |
| `custom.flatpak.enable` | Declarative Flatpak plus a weekly update timer |
| `custom.vr.enable` | VR runtime support |
| `custom.ai.claude.enable` / `custom.ai.copilot.enable` | Claude / GitHub Copilot integration in VS Code |
| `custom.debugProbes.enable` | udev rules for USB JTAG/SWD probes — see [docs/workstation.md](workstation.md#usb-debug-probes-udev) |
| `custom.binCompat.enable` | Symlinks `/bin/bash` for tools whose shebang expects it |

### Homelab services

All of these are enabled on `defiant`. See [docs/homelab-network.md](homelab-network.md).

| Option | What it does |
| --- | --- |
| `custom.dns` | unbound recursive resolver plus AdGuard Home, with split-horizon records |
| `custom.traefik` | Reverse proxy with ACME wildcard certificates via a DNS-01 provider |
| `custom.home-assistant` | Home Assistant service, `extraComponents`, HTTP/proxy wiring |
| `custom.mqtt` | Mosquitto broker |
| `custom.matter` | python-matter-server |
| `custom.zigbee` | Zigbee2MQTT |
| `custom.zwave` | Z-Wave JS server |
| `custom.adsb` | dump1090 ADS-B receiver |

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
