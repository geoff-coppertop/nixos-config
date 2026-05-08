{ pkgs, ... }:

{
  services.displayManager.gdm.enable = true;
  services.displayManager.gdm.wayland = true;
  services.desktopManager.gnome.enable = true;

  programs.dconf.enable = true;

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  environment.gnome.excludePackages = with pkgs; [
    baobab         # disk usage analyzer
    cheese         # photo booth
    eog            # image viewer
    epiphany       # web browser
    gedit          # text editor
    simple-scan    # document scanner
    totem          # video player
    evince         # document viewer
    file-roller    # archive manager
    geary          # email client
    seahorse       # password manager
    decibels       # audio player
    tali           # poker game
    iagno          # go game
    hitori         # sudoku game
    atomix         # puzzle game
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

  environment.systemPackages = with pkgs; [
    gnome-tweaks
    ulauncher
    gnomeExtensions.battery-health-charging
    gnomeExtensions.blur-my-shell
    gnomeExtensions.dash-to-dock
    gnomeExtensions.just-perfection
  ];
}
