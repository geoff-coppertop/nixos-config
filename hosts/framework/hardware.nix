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
  };

  swapDevices = [
    {device = "/dev/disk/by-partlabel/swap";}
  ];

  services.xserver.videoDrivers = ["amdgpu"];

  hardware.cpu.amd.updateMicrocode = true;
}
