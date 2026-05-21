{pkgs, ...}: {
  environment = {
    gnome.excludePackages = with pkgs; [
      baobab # disk usage analyzer
      cheese # photo booth
      eog # image viewer
      epiphany # web browser
      gedit # text editor
      simple-scan # document scanner
      totem # video player
      evince # document viewer
      file-roller # archive manager
      geary # email client
      seahorse # password manager
      decibels # audio player
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
      ulauncher
      gnomeExtensions.battery-health-charging
      gnomeExtensions.blur-my-shell
      gnomeExtensions.dash-to-dock
      gnomeExtensions.just-perfection
    ];
  };
  programs.dconf = {
    enable = true;
    profiles.gdm.databases = [
      {
        settings = {
          "org/gnome/desktop/interface" = {
            text-scaling-factor = 2.0;
          };
        };
      }
    ];
  };
  security.rtkit.enable = true;
  services = {
    desktopManager.gnome.enable = true;
    displayManager = {
      gdm = {
        enable = true;
        wayland = true;
      };
    };
    pipewire = {
      alsa = {
        enable = true;
        support32Bit = true;
      };
      enable = true;
      pulse.enable = true;
    };
    printing.enable = true;
    pulseaudio.enable = false;
  };
}
