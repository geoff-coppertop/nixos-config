{
  # Each DE owns its own greeter (GDM lives in gnome.nix). The DE-independent
  # layers are always present regardless of the choice: audio, the power/idle
  # chain, printing, and the DE-neutral home bits in
  # users/<name>/desktop-common.nix. The custom.desktop.environment enum
  # itself is declared in modules/desktop.nix.
  imports = [
    ./audio.nix
    ./gnome.nix
    ./power.nix
    ./printing.nix
  ];
}
