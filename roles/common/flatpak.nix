{
  services.flatpak = {
    enable = true;

    # Automatically add the default flathub remote repository
    remotes = [
      {
        name = "flathub";
        location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
      }
    ];

    # Declare your flatpaks here using their Flathub application IDs
    packages = [
      "com.github.tchx84.Flatseal"
      "com.bambulab.BambuStudio"
    ];

    # True declarative management:
    # Deletes any flatpak you install manually that isn't listed above.
    uninstallUnmanaged = true;

    # Optional: Automatically update your flatpaks on system activation/rebuild
    update.onActivation = true;
  };
}
