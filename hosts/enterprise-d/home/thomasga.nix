{
  imports = [
    ../../../users/thomasga/desktop.nix
    # Laptop-only internal-panel (eDP-1) monitor pin; the rest of GNOME is shared.
    ../../../users/thomasga/gnome-laptop.nix
  ];
  custom.ssh.identityKeyName = "ssh-id-ed25519-enterprise-d";
  programs.firefox.configPath = ".mozilla/firefox";
}
