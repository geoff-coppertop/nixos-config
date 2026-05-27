{
  config,
  lib,
  pkgs,
  ...
}: {
  options.custom.tpmLuks.enable = lib.mkEnableOption "TPM2-sealed LUKS root unlock";
  config = lib.mkIf config.custom.tpmLuks.enable {
    boot = {
      initrd = {
        availableKernelModules = ["tpm" "tpm_crb" "tpm_tis"];

        luks.devices.root = {
          # Removed hardcoded device string to allow Disko to define it safely
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
