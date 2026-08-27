{
  config,
  lib,
  ...
}: {
  config = lib.mkIf (config.custom.desktop.environment == "cosmic") {
    # System76's COSMIC desktop + its own greeter. This fully replaces GNOME/GDM
    # when selected — the two DE roles are mutually exclusive on
    # custom.desktop.environment, so there is no dual-session greeter.
    services.desktopManager.cosmic.enable = true;
    services.displayManager.cosmic-greeter.enable = true;

    # Suspend/hibernate policy: nothing to do here. The DE-independence contract
    # in profiles/desktop/power.nix covers COSMIC — cosmic-comp implements
    # ext-idle-notify-v1, so the idle-hint user service sets logind's IdleHint
    # at 240s and the logind/UPower chain owns everything from there.
    # cosmic-idle's own suspend timers are disabled on the home-manager side
    # (users/thomasga/cosmic.nix) so it never races logind.
    #
    # NOTE: fprintd login and the hibernate-resume greeter-blanking workaround
    # (profiles/desktop/gnome.nix, programs.dconf profiles.gdm) are GDM-specific and
    # do not carry over to cosmic-greeter. Verify fingerprint-at-login and
    # resume-from-hibernate behavior on hardware before treating COSMIC as the
    # daily driver.
  };
}
