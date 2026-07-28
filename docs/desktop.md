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
| `profiles/desktop/gnome.nix` | GNOME, GDM, system dconf settings |
| `profiles/desktop/audio.nix` | pipewire |
| `profiles/desktop/power.nix` | logind idle inhibitor |
| `modules/flatpak.nix` | Flatpak and Flatseal, as optional platform services |
| `modules/gaming.nix` | Steam |
| `profiles/common/base.nix` | Core system policy |
| `flake.nix` | Unfree package policy needed by Chrome and Steam |
| `users/common/gui-apps.nix` | Firefox, Fedora Media Writer, Bitwarden, Chrome, Signal Desktop, for any user importing it |
| `users/thomasga/desktop.nix` | Opts `thomasga` into that shared GUI set on desktop machines |
| `users/thomasga/vscode.nix` | VS Code through home-manager rather than the system profile |
| `users/thomasga/easyeffects.nix` | EasyEffects EQ for the Framework 13 speakers |

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

## EasyEffects (Framework Speaker EQ)

`users/thomasga/easyeffects.nix` enables `services.easyeffects` (home-manager)
as a per-user systemd service, sitting on top of pipewire
(`profiles/desktop/audio.nix`) to globally EQ the Framework 13's thin,
down-firing speakers. It relies on `programs.dconf.enable = true`, already set
system-wide by `profiles/desktop/gnome.nix`.

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
