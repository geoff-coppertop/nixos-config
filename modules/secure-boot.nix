{
  config,
  lib,
  pkgs,
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
    # tools/install.py runs sbctl from the installer's own environment, not
    # the installed system — without this, sbctl (needed for `sbctl status`,
    # re-enrollment, and `sbctl verify` after every host's own docs tell you
    # to run them) simply isn't on the machine post-install.
    environment.systemPackages = [pkgs.sbctl];
  };
}
