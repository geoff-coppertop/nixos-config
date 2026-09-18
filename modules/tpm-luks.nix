{
  config,
  lib,
  pkgs,
  ...
}: {
  options.custom.tpmLuks.enable = lib.mkEnableOption "TPM2-sealed LUKS root unlock";
  config = lib.mkIf config.custom.tpmLuks.enable {
    boot = {
      kernelModules = ["tpm_crb" "tpm_tis"];

      initrd = {
        availableKernelModules = ["tpm" "tpm_crb" "tpm_tis"];

        luks.devices.root = {
          # No `device` here: disko's own NixOS module sets
          # boot.initrd.luks.devices.root.device from each host's
          # disko.nix, so hardcoding a path here would duplicate (and
          # could drift from) that.
          preLVM = true;
          allowDiscards = true;
        };

        systemd = {
          emergencyAccess = true;
          enable = true;
        };
      };
    };

    environment.systemPackages = with pkgs; [
      tpm2-tools
    ];
  };
}
