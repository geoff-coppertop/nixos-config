{pkgs, ...}: {
  boot = {
    initrd = {
      availableKernelModules = ["tpm" "tpm_crb" "tpm_tis"];

      luks.devices.root = {
        device = "/dev/disk/by-partlabel/root";
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
}
