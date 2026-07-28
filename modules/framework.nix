{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkForce mkDefault;
in {
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
      login.fprintAuth = mkForce true;
      sudo.fprintAuth = true;
      gdm-fingerprint.fprintAuth = true;
    };

    # A Framework host almost always wants the control service too — one
    # switch instead of two separately-set booleans nothing links. mkDefault
    # so a host that wants the hardware support without the service can still
    # override it.
    services.framework-control.enable = mkDefault true;
  };
}
