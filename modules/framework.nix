{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  options.custom.framework.enable = mkEnableOption "Framework laptop specific configuration";

  config = mkIf config.custom.framework.enable {
    # Framework System Tool - CLI/GUI for fan, power, battery, and EC control
    environment.systemPackages = with pkgs; [
      framework-tool
    ];

    # Native Framework 2nd Gen fingerprint scanner support
    services.fprintd.enable = true;

    # PAM configuration for fingerprint authentication
    security.pam.services = {
      # mkForce is required here to override GDM's default 'false' assignment
      login.fprintAuth = lib.mkForce true; 
      sudo.fprintAuth = true;
      gdm-fingerprint.fprintAuth = true; 
    };
  };
}