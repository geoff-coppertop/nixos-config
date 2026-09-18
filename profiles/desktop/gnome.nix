{
  config,
  lib,
  pkgs,
  ...
}: let
  search-light = import ../../pkgs/search-light.nix {inherit pkgs;};
  eepresetselector = import ../../pkgs/eepresetselector.nix {inherit pkgs;};
in {
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
        eepresetselector
        gnomeExtensions.blur-my-shell
        gnomeExtensions.dash-to-dock
        gnomeExtensions.just-perfection
      ];
    };

    programs.dconf = {
      enable = true;
      # GDM runs its own GNOME Shell session in the background while the user
      # is logged in. On resume from hibernate, GDM's Mutter has the same
      # accumulated-idle-time problem as the user session: CLOCK_MONOTONIC
      # stops during hibernate, so GDM's idle time equals the pre-hibernate
      # idle duration on resume. Past idle-delay (default 300s), Mutter
      # immediately fires DPMS-off and the login screen goes dark.
      # idle-delay=0 ("never idle" in GNOME's schema) disables that tracking.
      #
      # Side effect: the greeter session then never sets logind IdleHint,
      # which would block IdleAction forever — the greeter-idle-hint timer
      # in profiles/desktop/power.nix compensates by marking any active
      # greeter-class session idle at the system level.
      #
      # idle-activation-enabled=false and lock-enabled=false prevent GDM's
      # screen shield from activating on logind's PrepareForSleep(false).
      #
      # Safety: dconf reads user-db:user before system-db:*, so the user's
      # own idle-delay=240 (home-manager, gnome.nix) always takes precedence
      # over this system-db value.
      #
      # Keyring note: pam_gnome_keyring.so can't unlock a password-protected
      # keyring during fingerprint auth (no password token available). On a
      # new machine, set the login keyring password to empty in Passwords &
      # Keys (seahorse) so it auto-unlocks at session start — acceptable
      # since the disk has LUKS full-disk encryption.
      profiles.gdm.databases =
        [
          {
            settings = {
              "org/gnome/desktop/screensaver" = {
                lock-enabled = false;
                idle-activation-enabled = false;
              };
              "org/gnome/desktop/session" = {
                idle-delay = lib.gvariant.mkUint32 0;
              };
            };
          }
        ]
        ++ lib.optionals config.services.fprintd.enable [
          {
            settings."org/gnome/login-screen" = {
              enable-fingerprint-authentication = true;
            };
          }
        ];
    };

    services = {
      # NixOS GDM module handles fprintd PAM but not the Settings UI side.
      # Expose GDM's gsettings schemas to user sessions so gnome-control-center
      # can find org.gnome.login-screen and show the fingerprint row.
      desktopManager.gnome = {
        enable = true;
        sessionPath = lib.optionals config.services.fprintd.enable [pkgs.gdm];
      };
      displayManager.gdm = {
        enable = true;
        # wayland: GDM/GNOME 50 dropped X11 entirely; the option no longer
        # has an effect and setting it is now a hard error.
        autoSuspend = false;
      };
    };
  };
}
