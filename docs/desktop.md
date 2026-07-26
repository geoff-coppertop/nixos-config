# Desktop And Workstation

Application ownership, desktop appearance, and the workstation tooling that
needs host-level support.

This doc applies the placement rule to the desktop specifically; the rule
itself, and where each layer's boundary sits, is
[docs/architecture.md § Placement Rule](architecture.md#placement-rule).

## Application Policy

### Removing unwanted desktop applications

Desktop-environment package pruning belongs in `roles/desktop/` (today,
`roles/desktop/gnome.nix`), not in per-user config. Typical candidates are
default utilities you do not use — a tour app, a help viewer, bundled games.

### Making GUI apps optional per user

Do not install apps like VS Code, Firefox, or Chrome globally if you want them to
appear only for users who choose them.

1. Keep them out of the global desktop role.
2. Add them in the relevant user module.
3. If several users may want them, factor them into a reusable opt-in module
   under `users/common/`.

```nix
{pkgs, ...}: {
  programs.firefox.enable = true;
  home.packages = [pkgs.firefox];
}
```

Chrome follows the same pattern, but `pkgs.google-chrome` also requires unfree
package policy, which is set in `flake.nix`.

### Current ownership

| File | Owns |
| --- | --- |
| `roles/desktop/gnome.nix` | GNOME, GDM, system dconf settings |
| `roles/desktop/audio.nix` | pipewire |
| `roles/desktop/power.nix` | logind idle inhibitor |
| `roles/common/flatpak.nix` | Flatpak and Flatseal, as optional platform services |
| `roles/common/gaming.nix` | Steam |
| `roles/common/base.nix` | Core system policy |
| `flake.nix` | Unfree package policy needed by Chrome and Steam |
| `users/common/gui-apps.nix` | Firefox, Fedora Media Writer, Bitwarden, Chrome, Signal Desktop, for any user importing it |
| `users/thomasga/desktop.nix` | Opts `thomasga` into that shared GUI set on desktop machines |
| `users/thomasga/vscode.nix` | VS Code through home-manager rather than the system profile |

## Theme, Background, And Desktop Preferences

Per-user desktop appearance belongs under that user's home-manager config, not
in the system desktop role.

- Put wallpaper files under `users/<name>/files/`.
- Link them into the home directory with `home.file` from a user module.
- Set dark mode, accent color, and wallpaper through the desktop environment's
  settings mechanism in a user module — today, GNOME's `dconf.settings`, as in
  `users/thomasga/gnome.nix`.

If the source wallpaper format is not one the desktop environment reliably
consumes directly, keep the upstream source in the repo and convert it during
the home-manager build.

For `thomasga` the concrete setup is:

- Source asset: `users/thomasga/files/wallpapers/space-shuttle.jxl`
- Conversion and GNOME settings: `users/thomasga/gnome.nix`
- Resulting linked wallpaper: `~/Pictures/Wallpapers/space-shuttle.png`

`users/thomasga/gnome.nix` converts the checked-in Fedora `.jxl` source to `.png`
with `pkgs.libjxl` and points both `picture-uri` and `picture-uri-dark` at the
generated PNG, avoiding any reliance on runtime JPEG XL wallpaper support.

System-wide dark mode is `custom.appearance.darkMode`, defined in
`users/common/appearance.nix`.

## draw.io And Obsidian

`users/thomasga/drawio.nix` installs `pkgs.drawio` (the standalone draw.io
desktop app) alongside Obsidian, and registers `*.drawio`/`*.dio` as a
shared-mime-info type (`application/vnd.jgraph.mxfile`) so file managers and
"Open With" dialogs default those extensions to draw.io instead of treating them
as plain XML.

Editing `.drawio` diagrams *inside* Obsidian notes requires the community plugin
"draw.io" (id `drawio`, by somesanity —
[somesanity/draw-io-obsidian](https://github.com/somesanity/draw-io-obsidian),
listed at
[community.obsidian.md/plugins/drawio](https://community.obsidian.md/plugins/drawio)).
It runs a bundled local Express server to edit diagrams fully offline. Its build
artifacts are published only as GitHub release assets, not committed to the repo,
so it is not vendored declaratively here.

Install it once per vault through Obsidian's UI: **Settings → Community plugins →
Browse**, search "draw.io", install, enable. Obsidian owns
`.obsidian/community-plugins.json` from then on — it rewrites the file live as
plugins are toggled — so this repo intentionally does not manage that file.
Managing it would clobber plugin state on every `nixos-rebuild switch`.

## Connect IQ SDK (Garmin)

`roles/dev/tools.nix` installs `connect-iq-sdk-manager` (a non-interactive Go CLI
replacement for Garmin's broken Electron/webkit2gtk SDK Manager GUI —
[lindell/connect-iq-sdk-manager-cli](https://github.com/lindell/connect-iq-sdk-manager-cli))
and a JDK, since the SDK's `monkeyc` compiler is a Java app.

Three things are automated so a fresh machine needs no interactive setup:

- `users/thomasga/connect-iq.nix` creates `~/.Garmin/ConnectIQ/Sdks` and accepts
  Garmin's SDK license agreement on first home-manager activation.
- `users/thomasga/shell.nix` adds the currently selected SDK's `bin/` to `PATH` on
  fish startup, so `monkeyc` is available without a manual export and stays
  correct across `sdk set <version>` switches.
- `modules/bin-compat.nix` (`custom.binCompat.enable`) symlinks `/bin/bash`, which
  `monkeyc`'s shebang expects and NixOS does not provide by default.

Manage SDK versions and devices with:

```bash
connect-iq-sdk-manager sdk list
connect-iq-sdk-manager sdk download <version>
connect-iq-sdk-manager sdk set <version>
connect-iq-sdk-manager device download
```

## USB Debug Probes (udev)

`custom.debugProbes.enable` (`modules/debug-probes.nix`) installs udev rules for
common USB JTAG/SWD debug probes — ST-Link, J-Link, FTDI-based adapters, and
CMSIS-DAP compatible devices, which includes the Raspberry Pi Debug Probe. The
rules themselves live in `modules/udev-rules/69-probe-rs.rules`, a verbatim copy
of the [probe-rs](https://probe.rs/)/OpenOCD project's udev rules (the same file
is also kept in the `helicopter-collective` repo's `.devcontainer/`), and are
loaded via `services.udev.packages` — **not** `services.udev.extraRules`. The
module also creates the `plugdev` group, the rules' `GROUP="plugdev"` fallback,
and `thomasga` is a member of it via `hosts/enterprise-d/configuration.nix`.

This is a system module rather than a user one, because the capability it grants
has to exist on the host. It is documented here, next to the workflow that needs
it, rather than buried in the module catalogue.

### Why `services.udev.packages` and not `extraRules`

This file's own name matters. It is called `69-probe-rs.rules` upstream
specifically so it sorts *before* systemd's own
`70-uaccess.rules`/`73-seat-late.rules`. Those files only queue the `uaccess`
ACL-granting builtin if a device is already `TAG=="uaccess"` at the point they
are evaluated, and udev processes all rule files in one linear pass sorted by
filename.

`services.udev.extraRules` merges its content into a single generated file always
named `99-local.rules`, which sorts *after* 73 — silently breaking the ACL grant
on every first-ever enumeration of a device, since our `TAG+="uaccess"`
assignment would run too late to be seen. `services.udev.packages` preserves each
file's own name in `/etc/udev/rules.d/`, restoring the intended ordering.

This bug is easy to miss because re-triggering an already-enumerated device
"fixes" it — the tag persists in that device's udev database entry from an
earlier pass — making it look like an intermittent timing race rather than a
deterministic ordering bug.

### Why the rules must live on the host

Embedded-dev devcontainers (e.g. `helicopter-collective`) do not create their own
USB device nodes. They bind-mount the host's `/dev/bus/usb` into the container
(via `devcontainer.json`'s `mounts`) and rely on `--userns=keep-id` to map the
container user to the host user's UID. Permission checks on that bind mount are
enforced by the kernel against the same device node the host owns, so whatever
the *host's* udev grants `thomasga` — through `plugdev` group membership and the
rules' `TAG+="uaccess"` ACL — is exactly what the container process gets. There is
no way to grant this access from inside the container image.

With the ordering fixed, a fresh `nixos-rebuild switch` plus a normal plug-in of
the probe is enough — no manual `udevadm trigger` or replug workaround.
