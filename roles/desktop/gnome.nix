{pkgs, ...}: let
  search-light = pkgs.stdenv.mkDerivation {
    pname = "gnome-shell-extension-search-light";
    version = "unstable-e08ef60";
    src = pkgs.fetchFromGitHub {
      owner = "icedman";
      repo = "search-light";
      rev = "e08ef60b09db4b10896e80e1e2ad8b85814c7ae8";
      sha256 = "sha256-G2yV7kuZ5/TTovhsgfJneRQvrHl4Hwkkbehe8YJah/A=";
    };
    nativeBuildInputs = [pkgs.glib];
    postPatch = ''
      # ungrab_accelerator expects an int but Object.keys() produces strings,
      # causing the release to silently fail and the subsequent re-grab to error.
      substituteInPlace keybinding.js \
        --replace-fail \
          'global.display.ungrab_accelerator(k)' \
          'global.display.ungrab_accelerator(parseInt(k))'

      # Remove dead Gio.DesktopAppInfo call that throws a GJS exception in newer
      # GNOME and aborts the deferred UI initialisation at the end of enable().
      sed -i '/Gio\.DesktopAppInfo\.new_from_filename/{N;N;d;}' extension.js

      # Set border-radius default to index 2 (18px) in the rads lookup table.
      # The rads array is [0,16,18,20,22,24,28,32]; valid slider range is 0-6.
      sed -i '/name="border-radius"/{n;s|<default>0</default>|<default>2.0</default>|}' \
        schemas/org.gnome.shell.extensions.search-light.gschema.xml
    '';
    buildPhase = ''
      runHook preBuild
      glib-compile-schemas --strict --targetdir=schemas/ schemas
      runHook postBuild
    '';
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
        autoSuspend = false;
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
  # Block logind's IdleAction while a user session is active so it only fires
  # for the GDM login screen. GNOME handles idle sleep for user sessions itself
  # via sleep-inactive-battery-type/timeout in the user's dconf settings.
  systemd.user.services."logind-idle-inhibitor" = {
    description = "Block logind idle action in user graphical sessions";
    wantedBy = ["graphical-session.target"];
    partOf = ["graphical-session.target"];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.systemd}/bin/systemd-inhibit --what=idle --who=gnome-session --why=session-active --mode=block ${pkgs.coreutils}/bin/sleep infinity";
      Restart = "on-failure";
      RestartSec = "1s";
    };
  };
}
