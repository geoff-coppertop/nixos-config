# Repository Architecture

How this repo is layered, where a given piece of configuration belongs, and what
the shared vocabulary (`custom.*`, `mkNixosSystem`) means.

## Layers

The configuration is a DAG of imports. Deciding which layer to edit is the main
architectural decision.

```text
flake.nix
  └── hosts/<machine>/        # machine-specific: hardware, disk, power
        └── roles/            # shared system policy: networking, GNOME, gaming
              └── modules/    # reusable NixOS features: backups, secrets, secure boot
                    └── users/<name>/   # personal: dotfiles, shell, apps (home-manager)
                          └── users/common/   # opt-in shared user modules
```

The repo is split by responsibility:

- `hosts/<machine>/` owns machine-specific hardware, power, and disk layout.
- `roles/` owns shared system policy such as base settings, networking, and the
  desktop baseline.
- `modules/` owns reusable system features such as btrfs, secrets, and secure boot.
- `users/<name>/` owns personal applications, dotfiles, shell behavior, and
  workflow tooling through home-manager.
- `secrets/` owns agenix-encrypted material that is safe to commit.

## Placement Rule

This is the canonical statement. Every other doc links here rather than
restating it.

- If it affects machine operation, put it in the system layer:
  `hosts/<machine>/` for machine-specific behavior, `roles/` for shared system
  policy, or `modules/` for a reusable NixOS feature.
- If it affects a person's workflow, put it in that user's home-manager config
  under `users/<name>/`, in a profile such as `users/<name>/desktop.nix`
  (full GUI) or `users/<name>/headless.nix` (CLI-only).
- If several users may want it, create a reusable opt-in user module under
  `users/common/` and import it from the relevant profile instead of forcing it
  globally.

## One File Per Concern

Favor a new file over adding an unrelated setting to an existing catch-all file,
anywhere in the tree — `roles/`, `modules/`, `users/`, `hosts/`.

The worked example is networking. Three separate files, three separate concerns:

| File | Concern |
| --- | --- |
| `roles/common/base.nix` | Unconditional OS settings |
| `roles/common/wifi.nix` | NetworkManager profiles and Wi-Fi credentials |
| `roles/common/networking.nix` | Network discovery (avahi/mDNS) |

When adding a setting, ask whether it fits an existing file's concern or needs a
new one. Do not default to the nearest catch-all just because it is already
imported.

## The Aggregator Pattern

Adding a new file is always three steps, in this order, everywhere in the tree:

1. Create the file — `modules/<feature>.nix`, `roles/common/<concern>.nix`,
   `users/common/<app>.nix`.
2. Add one import line to the sibling `default.nix`.
3. Opt in where it applies — `custom.<feature>.enable = true;` in a host
   configuration, or an import in a user profile such as
   `users/thomasga/desktop.nix`.

It holds identically for `modules/`, `roles/common/`, `roles/dev/`,
`roles/desktop/`, and `users/`.

**Step 2 is the one that fails silently.** A `.nix` file no `default.nix`
imports is never evaluated, so it raises no error — it simply does nothing.
`nix flake check` never sees it, and `deadnix` reports unused *bindings*, not
unimported *files*. `modules/ssh-known-hosts.nix` sat unimported from the commit
that added it, which meant SSH host-key pinning quietly did nothing.

`tools/check_orphan_nix.py` now enforces step 2. It runs as a pre-commit hook
and as a flake check, walking import edges out from `flake.nix` and failing on
anything it cannot reach. If a file is deliberately not imported, add it to
`ALLOWED_ORPHANS` in that script with a comment explaining why.

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
| `roles/common/` | Base OS settings, users, NetworkManager Wi-Fi profiles, network discovery, backups, gaming, Flatpak |
| `roles/desktop/` | GNOME baseline, audio (pipewire), power/idle policy |
| `roles/dev/` | Dev tooling: GitHub CLI, container runtime, network tools |
| `modules/` | Opt-in reusable NixOS features (see the `custom.*` catalogue below) |
| `modules/udev-rules/` | Verbatim upstream udev rule files loaded via `services.udev.packages` |
| `users/thomasga/` | Git, SSH, fish shell, GNOME dconf, VS Code, wallpaper, per-machine profiles |
| `users/common/` | Shared opt-in user modules: CLI tools, GUI apps, appearance |
| `lib/` | `apps.nix`, `checks.nix`, `devshell.nix`, `nas.nix`, `nixos-system.nix`, `ssh-hosts.nix`, `traefik-route.nix` |
| `secrets/` | agenix `.age` files (safe to commit) plus `secrets/secrets.nix` (recipient declarations) |
| `pkgs/` | Custom package builds: `framework-control`, `search-light`, `connect-iq-sdk-manager-cli` |
| `tools/` | Python provisioning and secret helpers (plus one shell script, `hibernate-test-report.sh`) |
| `docs/` | This documentation tree |

## Custom Options

Modules expose behavior through `custom.*` options rather than direct NixOS
options, so a host configuration reads as a list of intents.

Most are declared under `modules/`, but not all — `custom.backups` is declared in
`roles/common/backups.nix` and `custom.users` in `roles/common/users.nix`.

### System policy

| Option | Declared in | What it does |
| --- | --- | --- |
| `custom.isLaptop` | `roles/common/base.nix` | Gates AC-power-sensitive maintenance jobs (NAS backups, auto-upgrade, Flatpak auto-update) |
| `custom.users` | `roles/common/users.nix` | Declares user accounts, groups, and SSH authorized keys |
| `custom.backups` | `roles/common/backups.nix` | Per-entry restic backups to the NAS over SMB or NFS |
| `custom.wifi.enable` | `roles/common/wifi.nix` | NetworkManager `ensureProfiles` Wi-Fi profiles |
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
| `custom.framework.enable` | Framework laptop drivers (fingerprint reader, keyboard brightness, charge limit) plus the `framework-control` GUI |

### Desktop and workstation

| Option | What it does |
| --- | --- |
| `custom.appearance.darkMode` | System-wide dark mode (home-manager, `users/common/appearance.nix`) |
| `custom.cli.shell` | Selects which shell the user CLI modules activate |
| `custom.gaming.enable` | Steam |
| `custom.flatpak.enable` | Declarative Flatpak plus a weekly update timer |
| `custom.vr.enable` | VR runtime support |
| `custom.ai.claude.enable` / `custom.ai.copilot.enable` | Claude / GitHub Copilot integration in VS Code |
| `custom.debugProbes.enable` | udev rules for USB JTAG/SWD probes — see [docs/desktop.md](desktop.md#usb-debug-probes-udev) |
| `custom.binCompat.enable` | Symlinks `/bin/bash` for tools whose shebang expects it |

### Homelab services

All of these are enabled on `defiant`. See [docs/homelab.md](homelab.md).

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

## Defining a New Machine

1. Create `hosts/<machine-name>/`.
2. Add `hosts/<machine-name>/configuration.nix` (imports hardware, power, disk).
3. Add `hosts/<machine-name>/hardware.nix` (hardware-scan output).
4. Add `hosts/<machine-name>/power.nix` (power and hibernate policy).
5. Add `hosts/<machine-name>/disko.nix` (disk layout, if provisioning from this repo).
6. Add `hosts/<machine-name>/default.nix` attaching home-manager for each user.
7. Register the machine in `flake.nix` under `nixosConfigurations`:

```nix
nixosConfigurations."<machine-name>" = mkNixosSystem {
  system = "x86_64-linux"; # or "aarch64-linux" for ARM machines
  extraModules = [
    ./hosts/<machine-name>
    # add machine-specific modules as needed:
    # disko.nixosModules.disko            (physical machines with declarative disk layout)
    # lanzaboote.nixosModules.lanzaboote  (Secure Boot)
    # nixos-wsl.nixosModules.default      (WSL machines)
  ];
};
```

Then follow [docs/provisioning.md](provisioning.md) to enroll and install it.

## Change GNOME Or Kernel Policy Later

The current baseline comes from
`nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"` in `flake.nix`.

To change the baseline:

1. Change the `nixpkgs` input to a different branch or revision.
2. Update the lock file.
3. Rebuild and test.

That is the correct place to move between more conservative and more aggressive
GNOME/kernel update policies.
