{
  config,
  lib,
  pkgs,
  ...
}: let
  search-light = import ../../pkgs/search-light.nix {inherit pkgs;};
  eepresetselector = import ../../pkgs/eepresetselector.nix {inherit pkgs;};
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
    # GDM runs its own GNOME Shell session in the background while the user is
    # logged in. On resume from hibernate, GDM's Mutter has the same
    # accumulated-idle-time problem as the user session: CLOCK_MONOTONIC stops
    # during hibernate, so on resume GDM's idle time equals the pre-hibernate
    # idle duration. If that exceeds idle-delay (default 300 s), Mutter
    # immediately fires DPMS-off and the login screen goes dark.
    #
    # idle-delay=0 means "never idle" in GNOME's schema — it disables idle
    # tracking in GDM's session so the screen can never blank due to
    # accumulated idle time on resume.
    #
    # Side effect: the greeter session then never sets logind IdleHint, which
    # would block IdleAction (login-screen auto-suspend) forever. The
    # greeter-idle-hint timer in profiles/desktop/power.nix compensates by
    # marking any active greeter-class session idle at the system level.
    #
    # idle-activation-enabled=false and lock-enabled=false prevent GDM's screen
    # shield from activating when logind sends PrepareForSleep(false) on resume.
    #
    # Safety: dconf reads user-db:user before system-db:*, so user-level dconf
    # settings (set via home-manager) always take precedence over this system-db
    # entry. The user's idle-delay=240 in gnome.nix cannot be overridden by this
    # GDM system-db value.
    #
    # Keyring note: pam_gnome_keyring.so cannot unlock a password-protected
    # keyring during fingerprint auth because no password token is available.
    # On a new machine, open Passwords & Keys (seahorse) and set the login
    # keyring password to empty so it auto-unlocks at session start.
    # Acceptable because the disk is protected by LUKS full-disk encryption.
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
      autoSuspend = false;
    };
    printing.enable = true;
  };
}
