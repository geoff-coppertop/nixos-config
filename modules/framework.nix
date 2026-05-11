{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  options.custom.framework.enable = mkEnableOption "Framework laptop specific configuration";

  config = mkIf config.custom.framework.enable {
    # Framework Control - GUI for fan, power, battery, and EC control
    environment.systemPackages = with pkgs; [
      framework-control
    ];

    # Fingerprint scanner support
    services.fprintd = {
      enable = true;
      tod = {
        enable = true;
        driver = pkgs.libfprint-2-tod1-vfs0090;
      };
    };

    # PAM configuration for fingerprint authentication
    security.pam.services = {
      login.fprintAuth = true;
      sudo.fprintAuth = true;
      gdm.fprintAuth = true;
    };

    # Allow access to input devices for fingerprint scanner
    services.udev.packages = with pkgs; [
      libfprint-2-tod1-vfs0090
    ];
  };
}
