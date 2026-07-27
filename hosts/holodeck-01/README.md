# holodeck-01

NixOS running as a WSL2 distribution on Windows (`x86_64-linux`). Headless
development environment — `roles/desktop` is deliberately not imported, since
there is no display server.

## Machine Files

| File | Purpose |
| --- | --- |
| `configuration.nix` | WSL settings, user account, backups, sshd |
| `default.nix` | home-manager attachment |
| `secrets.nix` | `age.secrets` declarations for this host |
| `home/thomasga.nix` | Per-machine home-manager profile (headless) |
| `provision-type` | `wsl` |

## WSL Specifics

```nix
wsl = {
  enable = true;
  defaultUser = "thomasga";
  startMenuLaunchers = true;
};
```

The `nixos-wsl` flake input supplies the module; it is passed to this host in
`flake.nix` as `nixos-wsl.nixosModules.default`. `system.stateVersion` is
`"25.11"`.

## Rebuilding In Place

Run from inside the WSL distro. Either fetch straight from GitHub:

```bash
sudo nixos-rebuild switch --flake github:geoff-coppertop/nixos-config#holodeck-01
```

or use a local checkout:

```bash
sudo nixos-rebuild switch --flake /path/to/nixos-config#holodeck-01
```

This requires the age identity to already be installed at
`/var/lib/agenix/identity`.

## Fresh Bootstrap Is Not Available

`install.py`'s WSL flow — fetch NixOS-WSL, `wsl --import`, apply the flake — was
pulled out of the Python tooling rewrite pending real validation. Unlike the
disko flow, which was tested thoroughly, it had never been run end to end. It
will return in a follow-up once there is an environment to validate it against,
or may not return at all if WSL usage here winds down as expected.

If you need to bootstrap a **new** WSL machine before that lands, ask first
rather than reaching for old instructions — nothing in this repo currently
automates it.

WSL2 itself must be enabled on Windows first. If it is not, run `wsl --install`
from an elevated PowerShell and reboot once.

None of this affects rebuilding `holodeck-01`, which already exists and boots
normally.

## Backups

Backs up `thomasga`'s home directory to the NAS at `192.168.1.231`, share
`Personal-Drive/backups`, using
`/run/agenix/thomasga/nas-smb-credentials`. `custom.isLaptop` is unset, so
backups are not AC-gated on this host.

See [docs/backups.md](../../docs/backups.md).
