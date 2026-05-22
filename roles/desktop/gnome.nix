{pkgs, ...}: let
  search-light = pkgs.stdenv.mkDerivation {
    pname = "gnome-shell-extension-search-light";
    version = "unstable-4e93e0e";
    src = pkgs.fetchFromGitHub {
      owner = "icedman";
      repo = "search-light";
      rev = "4e93e0e3e2fba8512dfd588177b7a6a2a71c9f1e";
      sha256 = "02zdc3jp0xpkds61x22hxpnmirxq8m5ici971bdcy64nd9zyck4r";
    };
    nativeBuildInputs = [pkgs.glib];
    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/gnome-shell/extensions/search-light@icedman.github.com
      cp -r . $out/share/gnome-shell/extensions/search-light@icedman.github.com/
      if [ -d schemas ]; then
        mkdir -p $out/share/glib-2.0/schemas
        cp schemas/*.xml $out/share/glib-2.0/schemas/
        glib-compile-schemas $out/share/glib-2.0/schemas/
      fi
      runHook postInstall
    '';
    meta.description = "Take the apps search out of the overview";
  };
in {
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
      search-light
      gnomeExtensions.battery-health-charging
      gnomeExtensions.blur-my-shell
      gnomeExtensions.dash-to-dock
      gnomeExtensions.just-perfection
    ];
  };
  programs.dconf = {
    enable = true;
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
