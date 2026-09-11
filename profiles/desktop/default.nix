{
  # Each DE owns its own greeter (GDM lives in gnome.nix and hyprland.nix; both
  # use it). The DE-independent layers are always present regardless of the
  # choice: audio, the power/idle chain, printing, and the DE-neutral home bits
  # in users/<name>/desktop-common.nix. The custom.desktop.environment enum
  # itself is declared in modules/desktop.nix.
  imports = [
    ./audio.nix
    ./gnome.nix
    ./hyprland.nix
    ./power.nix
    ./printing.nix
  ];
}
