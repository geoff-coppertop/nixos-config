{
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    initrd.systemd.enable = true;
    resumeDevice = "/dev/disk/by-partlabel/swap";
  };

  fileSystems = {
    "/" = {
      device = "/dev/mapper/root";
      fsType = "btrfs";
      options = ["subvol=@"];
    };

    "/home" = {
      device = "/dev/mapper/root";
      fsType = "btrfs";
      options = ["subvol=@home"];
    };

    "/boot" = {
      device = "/dev/disk/by-partlabel/boot";
      fsType = "ext4";
    };

    "/boot/efi" = {
      device = "/dev/disk/by-partlabel/ESP";
      fsType = "vfat";
    };
  };

  swapDevices = [
    {device = "/dev/disk/by-partlabel/swap";}
  ];

  services.xserver.videoDrivers = ["amdgpu"];

  hardware.cpu.amd.updateMicrocode = true;
}
