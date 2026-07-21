{
  config,
  lib,
  ...
}: {
  # GDM is the login manager for every desktop environment on this host;
  # custom.desktop.environment (roles/desktop/default.nix) only selects the
  # session GDM launches. Everything here is DE-independent: fingerprint-at-
  # login, the greeter dconf profile, and the greeter idle-hint contract
  # (roles/desktop/power.nix) all live at the greeter/PAM layer and behave the
  # same whichever session is selected.
  #
  # GDM's own greeter is a GNOME Shell session, so gnome-shell stays in the
  # closure regardless of the selected session. That is the accepted cost of a
  # reliable fingerprint-at-login row.
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
    # greeter-idle-hint timer in roles/desktop/power.nix compensates by
    # marking any active greeter-class session idle at the system level.
    #
    # idle-activation-enabled=false and lock-enabled=false prevent GDM's screen
    # shield from activating when logind sends PrepareForSleep(false) on resume.
    #
    # Safety: dconf reads user-db:user before system-db:*, so user-level dconf
    # settings (set via home-manager) always take precedence over this system-db
    # entry. A user session's own idle-delay cannot be overridden by this GDM
    # system-db value.
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
    displayManager.gdm = {
      enable = true;
      wayland = true;
      autoSuspend = false;
    };
    printing.enable = true;
  };
}
