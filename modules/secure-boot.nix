{
  config,
  lib,
  ...
}: {
  options.custom.secureBoot.enable = lib.mkEnableOption "lanzaboote secure boot";
  config = lib.mkIf config.custom.secureBoot.enable {
    boot = {
      loader = {
        systemd-boot.enable = lib.mkForce false;
        efi = {
          canTouchEfiVariables = true;
          efiSysMountPoint = "/boot";
        };
      };
      lanzaboote = {
        enable = true;
        pkiBundle = "/etc/secureboot";
      };
    };
  };
}
