# Desktop

Which layer owns a graphical application, and how a user's desktop looks.

What the *machine* provides — which desktop environment runs, audio,
idle/suspend policy, the dev toolchain — is
[docs/workstation.md](workstation.md). This doc is the personal layer on top.
The layering rule it applies is
[docs/architecture.md § Placement Rule](architecture.md#placement-rule).

## Application Policy

### Making GUI apps optional per user

Do not install apps like VS Code, Firefox, or Chrome globally if you want them to
appear only for users who choose them.

1. Keep them out of the global desktop profile.
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
| `profiles/desktop/gnome.nix` | GNOME, GDM, system dconf settings — active only when `custom.desktop.environment = "gnome"` |
| `profiles/desktop/hyprland.nix` | Hyprland, GDM, portals, hyprlock PAM — active only when `custom.desktop.environment = "hyprland"` |
| `profiles/desktop/printing.nix` | CUPS printing, DE-independent |
| `profiles/desktop/audio.nix` | pipewire |
| `profiles/desktop/power.nix` | logind idle inhibitor |
| `modules/flatpak.nix` | Flatpak and Flatseal, as optional platform services |
| `modules/gaming.nix` | Steam |
| `profiles/common/base.nix` | Core system policy |
| `flake.nix` | Unfree package policy needed by Chrome and Steam |
| `users/common/gui-apps.nix` | Firefox, Fedora Media Writer, Bitwarden, Chrome, Signal Desktop, for any user importing it |
| `users/thomasga/desktop.nix` | Opts `thomasga` into that shared GUI set on desktop machines |
| `users/thomasga/desktop-common.nix` | DE-neutral home bits: wallpaper decode, avatar, Steam-shortcut cleanup, launcher hygiene — loaded regardless of the selected desktop |
| `users/thomasga/vscode.nix` | VS Code through home-manager rather than the system profile |
| `users/thomasga/easyeffects.nix` | EasyEffects EQ for the Framework 13 speakers |
| `users/thomasga/orca-slicer.nix` | OrcaSlicer, the 3D-print slicer GUI |

## Theme, Background, And Desktop Preferences

Per-user desktop appearance belongs under that user's home-manager config, not
in the system desktop profile.

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
- Conversion (DE-neutral): `users/thomasga/desktop-common.nix`
- GNOME settings: `users/thomasga/gnome.nix`; Hyprland `hyprpaper`:
  `users/thomasga/hyprland.nix`
- Resulting linked wallpaper: `~/Pictures/Wallpapers/space-shuttle.png`

`users/thomasga/desktop-common.nix` converts the checked-in Fedora `.jxl` source
to `.png` with `pkgs.libjxl` and links it to a stable path so any desktop
environment's config can point at it without redoing the conversion.
`users/thomasga/gnome.nix` points both `picture-uri` and `picture-uri-dark` at
that generated PNG; `users/thomasga/hyprland.nix` preloads the same PNG in
`hyprpaper`. Either way avoids any reliance on runtime JPEG XL wallpaper
support.

Any new local asset file under `users/` — an avatar, a wallpaper, a static
image handed to `.source` or interpolated into a builder — must be wrapped
with `lib/local-file.nix` rather than passed as a bare path literal; see
[docs/architecture.md § Local Files As Build Inputs](architecture.md#local-files-as-build-inputs)
for why. `users/thomasga/account.nix`'s `avatar` and
`users/thomasga/desktop-common.nix`'s wallpaper conversion are the existing
examples.

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

## OrcaSlicer

`users/thomasga/orca-slicer.nix` installs `pkgs.orca-slicer`, the native
desktop slicer GUI, for local model prep, preview, and slicing on
enterprise-d. Its printer profiles and network-plugin settings live in
`~/.config/OrcaSlicer` and are configured through the app's own first-run
wizard, not declaratively — same as other account-bound apps in this repo
(Signal, Discord, Bitwarden).

This is separate from the OrcaSlicer *sidecar* on `reliant`
(`custom.bambuddy.slicerSidecar` in `modules/bambuddy.nix`): that's a
headless, patched OrcaSlicer CLI wrapped in a container for Bambuddy's
server-side slicing, with no GUI and no shared configuration with this
desktop package.

nixpkgs' `orca-slicer` package references its icon by theme name
(`Icon=OrcaSlicer`) rather than a path, and ships no scalable SVG — only
hicolor PNGs. Hicolor lookup by name doesn't resolve through the
home-manager profile, so GNOME's app grid falls back to a generic icon.
`users/thomasga/orca-slicer.nix` overrides the upstream `.desktop` entry
(same XDG_DATA_DIRS-precedence trick as the draw.io and Signal overrides)
to point `icon` at the packaged 192px PNG directly.

## EasyEffects (Framework Speaker EQ)

`users/thomasga/easyeffects.nix` enables `services.easyeffects` (home-manager)
as a per-user systemd service, sitting on top of pipewire
(`profiles/desktop/audio.nix`) to globally EQ the Framework 13's thin,
down-firing speakers. It relies on `programs.dconf.enable = true`, already set
system-wide by whichever desktop profile is active (`profiles/desktop/gnome.nix`
or `profiles/desktop/hyprland.nix`).

Four community presets from
[ceiphr/ee-framework-presets](https://github.com/ceiphr/ee-framework-presets)
(`gracefu`, `kieran_levin`, `lappy_mctopface`, `philonmetal`) are fetched with
`pkgs.fetchurl`, pinned to a commit and content-hashed, and written straight to
`xdg.dataFile."easyeffects/output/<name>.json"` — matching the pattern used
elsewhere in this repo for third-party sources (`pkgs/search-light.nix`,
`pkgs/framework-control.nix`) rather than vendoring a copy of someone else's
files into git. To pick up an upstream preset change, bump the `rev` and the
corresponding `hash` in `users/thomasga/easyeffects.nix` together.

`lappy_mctopface` (tuned for on-lap use) loads at login via
`services.easyeffects.preset`; `kieran_levin` (flat, tuned for on-a-table use)
is the recommended alternative. Switch between them anytime from the
EasyEffects UI's preset dropdown — the daemon reloads without a rebuild. The
repo's "louder" preset variants were intentionally left out: upstream notes
they can introduce ~1ms audio artifacts on pause/play.

`users/thomasga/gnome.nix` also lists
`"eepresetselector@ulville.github.io"` in `enabled-extensions`, turning on the
top-panel preset switcher packaged in `pkgs/eepresetselector.nix` (see
`docs/workstation.md` for the packaging side) — a faster way to swap between
the four presets above than opening the EasyEffects UI. Its default
keybindings (`<Control><Super>o`/`i`/`b` to cycle output/input presets and
toggle global bypass) don't collide with anything else this repo sets, so no
per-extension dconf settings block was added; defaults are left as-is.

## Known Gotchas

- **VS Code launches with `disable-hardware-acceleration = true`.** amdgpu
  invalidates GPU context on hibernate resume, crashing VS Code's Chromium GPU
  process (SIGTRAP); no upstream issue is cited, just "until fixed upstream" —
  see `users/thomasga/vscode.nix:34`.
- **Signal's `.desktop` entry launches with `--disable-gpu`.** Same amdgpu
  hibernate-resume GPU-context crash as VS Code above, worked around by
  overriding the upstream `.desktop` entry; no upstream issue is cited either
  — see `users/common/gui-apps.nix:31-32`.
- **OrcaSlicer's `.desktop` entry is overridden to set `icon` to a store
  path.** Upstream references its icon by theme name and ships no scalable
  SVG; hicolor lookup by name doesn't resolve through the home-manager
  profile, so the app grid shows a generic icon otherwise — see
  `users/thomasga/orca-slicer.nix`.
