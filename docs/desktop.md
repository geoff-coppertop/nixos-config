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
