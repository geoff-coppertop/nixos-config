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

        # No device string here: Disko defines it.
        luks.devices.root.allowDiscards = true;

        systemd.emergencyAccess = true;
      };
    };

    environment.systemPackages = with pkgs; [
      tpm2-tools
    ];
  };
}
