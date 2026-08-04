{
  config,
  lib,
  pkgs,
  ...
}: {
  # Hyprland session, active only when custom.desktop.environment = "hyprland".
  # Per this repo's model each DE owns its own greeter (see modules/desktop.nix
  # and profiles/desktop/gnome.nix); this session keeps GDM — the same greeter
  # GNOME uses — because it's the reliable path for fingerprint-at-login. The
  # user-facing compositor config (bar, launcher, keybinds, idle/lock) is
  # home-manager in users/thomasga/hyprland.nix.
  config = lib.mkIf (config.custom.desktop.environment == "hyprland") {
    # Installs Hyprland, registers the wayland-session file GDM lists, and wires
    # xdg-desktop-portal-hyprland (screencopy/screenshot backend).
    programs.hyprland.enable = true;

    # GTK apps need a file-chooser portal; the hyprland portal doesn't provide
    # one. Prefer hyprland for the interfaces it implements, gtk for the rest.
    xdg.portal = {
      extraPortals = [pkgs.xdg-desktop-portal-gtk];
      config.common.default = ["hyprland" "gtk"];
    };

    # hyprlock authenticates through its own PAM stack. Referencing the service
    # creates /etc/pam.d/hyprlock; fprintAuth enrols the fingerprint reader so
    # the lock screen unlocks by fingerprint like the GDM greeter, with password
    # fallback (same pattern as sudo in modules/framework.nix).
    security.pam.services.hyprlock.fprintAuth = true;

    # GDM greeter, mirroring profiles/desktop/gnome.nix (each DE owns its
    # greeter, and GNOME/Hyprland both use GDM; the two blocks are mutually
    # exclusive via the DE gate, so only one is ever active). dconf is also
    # enabled here because the home-manager dark-mode dconf
    # (users/common/appearance.nix) needs it and GNOME's copy is gated off
    # under this session.
    programs.dconf = {
      enable = true;
      # See profiles/desktop/gnome.nix for the full rationale: idle-delay=0
      # stops GDM's Mutter greeter DPMS-blanking on hibernate resume; lock/idle-
      # activation off stop the screen shield on PrepareForSleep(false); the
      # greeter-idle-hint timer in profiles/desktop/power.nix compensates for
      # the greeter then never setting logind IdleHint.
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

    services.displayManager.gdm = {
      enable = true;
      # wayland: GDM/GNOME 50 dropped X11 entirely; the option no longer has an
      # effect and setting it is now a hard error (see profiles/desktop/gnome.nix).
      autoSuspend = false;
    };

    # No Secret Service (gnome-keyring) is installed under Hyprland — NAS mounts
    # are declarative CIFS (modules/network-drives.nix, DE-independent), so
    # nothing here needs a keyring. Apps that lean on libsecret (Bitwarden/
    # Signal/VS Code) will have no backing store under this session; if that
    # becomes a problem, add gnome-keyring as a standalone daemon here
    # (services.gnome.gnome-keyring.enable = true) — the daemon only, not the
    # GNOME desktop.
  };
}
