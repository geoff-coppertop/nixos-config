# NixOS Config

This repo is the source of truth for machine setup, user setup, secrets wiring,
and update policy across four machines. Everything is declarative and committed;
nothing is configured by hand after install.

## Machines

| Machine | Type | Arch | Entrypoint | Host doc |
| --- | --- | --- | --- | --- |
| `enterprise-d` | Framework laptop | `x86_64-linux` | `hosts/enterprise-d/configuration.nix` | [README](hosts/enterprise-d/README.md) |
| `holodeck-01` | NixOS on WSL2 | `x86_64-linux` | `hosts/holodeck-01/configuration.nix` | [README](hosts/holodeck-01/README.md) |
| `excelsior` | HP EliteDesk 800 G2 Mini game server | `x86_64-linux` | `hosts/excelsior/configuration.nix` | [README](hosts/excelsior/README.md) |
| `reliant` | Gigabyte GB-BXi5-4200 "Brix" mini PC, homelab server | `x86_64-linux` | `hosts/reliant/configuration.nix` | [README](hosts/reliant/README.md) |

Naming convention and the rest of the layout are in
[docs/architecture.md](docs/architecture.md).

## Quick Start

Requires Nix 2.18+ with `experimental-features = nix-command flakes`. Enter the
dev shell (`nix develop`) and see [docs/operations.md](docs/operations.md) for
everything else — lint, build, rebuild, updates.

## Documentation

| Doc | Answers |
| --- | --- |
| [docs/architecture.md](docs/architecture.md) | Where does this setting belong? What is `custom.*`? |
| [docs/operations.md](docs/operations.md) | How do I set up a workstation, rebuild, update, or read CI? |
| [docs/backups.md](docs/backups.md) | How do restic-to-NAS backups work, and how do I enable one? |
| [docs/provisioning.md](docs/provisioning.md) | How do I define and install a machine from scratch — USB, SD card, or WSL? |
| [docs/secrets.md](docs/secrets.md) | How do agenix secrets and SSH keys work? How do I create, rotate, or rekey one? What goes in each file? |
| [docs/users.md](docs/users.md) | How do I add a user, attach home-manager, or manage dotfiles? |
| [docs/desktop.md](docs/desktop.md) | How do I install an app for just me, or change my theme and wallpaper? |
| [docs/workstation.md](docs/workstation.md) | What does this machine provide — desktop environment, audio, containers, debug probes? |
| [docs/homelab-network.md](docs/homelab-network.md) | How do Traefik and DNS compose on reliant? |
| [docs/smart-home.md](docs/smart-home.md) | How do Home Assistant, Zigbee, and Z-Wave fit together? |

## Repository Layout

```text
flake.nix     entry point: inputs, dev shell, checks, apps, host and home configs
hosts/        machine-specific hardware, disk, power, and service selection
profiles/     preset bundles a host opts into by name: common, desktop, dev
modules/      custom.* feature modules: users, wifi, backups, secure boot, ...
users/        home-manager: per-user profiles plus shared opt-in modules
lib/          flake helpers: mkNixosSystem, checks, dev shell, apps, inventories
pkgs/         custom package builds
secrets/      agenix .age files (safe to commit) and recipient declarations
tools/        Python provisioning and secret helpers
docs/         the documentation above
```

## Contributing

- One file per concern. Do not add an unrelated setting to a catch-all file just
  because it is already imported — see
  [docs/architecture.md](docs/architecture.md#one-file-per-concern).
- Nix must pass `alejandra`, `statix`, and `deadnix`; Markdown must pass
  `markdownlint`. Run `nix develop -c pre-commit run --all-files` before pushing.
- Never create files under `secrets/` by hand. Use
  `nix run .#secret-edit -- <file>`.
- CI runs the same lint and eval checks plus a native build of all three hosts.
  See [docs/operations.md](docs/operations.md#lint-format-and-ci).
