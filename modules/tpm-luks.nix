{ pkgs, ... }:

{
  boot.initrd.systemd.enable = true;
  boot.initrd.systemd.emergencyAccess = true;

  boot.initrd.luks.devices.root = {
    device = "/dev/disk/by-partlabel/root";
    preLVM = true;
    allowDiscards = true;
  };

  boot.initrd.availableKernelModules = [ "tpm" "tpm_crb" "tpm_tis" ];

  environment.systemPackages = with pkgs; [
    tpm2-tools
  ];
}
