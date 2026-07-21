{
  config,
  lib,
  pkgs,
  ...
}: let
  search-light = import ../../pkgs/search-light.nix {inherit pkgs;};
in {
  # Only installed when the GNOME session is selected. GDM, dconf, and printing
  # are DE-independent and live in roles/desktop/login.nix instead.
  config = lib.mkIf (config.custom.desktop.environment == "gnome") {
    environment = {
      gnome.excludePackages = with pkgs; [
        baobab # disk usage analyzer
        cheese # photo booth
        eog # image viewer
        epiphany # web browser
        gedit # text editor
        simple-scan # document scanner
        totem # video player
        file-roller # archive manager
        geary # email client
        decibels # audio player
        gnome-console # we use Ghostty
        tali # poker game
        iagno # go game
        hitori # sudoku game
        atomix # puzzle game
        gnome-calculator
        gnome-calendar
        gnome-characters
        gnome-clocks
        gnome-contacts
        gnome-font-viewer
        gnome-logs
        gnome-maps
        gnome-music
        gnome-photos
        gnome-screenshot
        gnome-weather
        gnome-connections
        gnome-tour
        gnome-initial-setup
        gnome-text-editor
        yelp
      ];
      systemPackages = with pkgs; [
        gnome-tweaks
        search-light
        gnomeExtensions.blur-my-shell
        gnomeExtensions.dash-to-dock
        gnomeExtensions.just-perfection
      ];
    };

    # NixOS GDM module handles fprintd PAM but not the Settings UI side.
    # Expose GDM's gsettings schemas to user sessions so gnome-control-center
    # can find org.gnome.login-screen and show the fingerprint row.
    services.desktopManager.gnome = {
      enable = true;
      sessionPath = lib.optionals config.services.fprintd.enable [pkgs.gdm];
    };
  };
}
