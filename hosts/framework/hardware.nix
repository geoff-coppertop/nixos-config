{
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    initrd = {
      systemd = {
        enable = true;
        services = {
          systemd-udev-settle = {
            wantedBy = ["initrd.target"];
          };
          systemd-activate-swap = {
            after = ["systemd-udev-settle.service"];
            requires = ["systemd-udev-settle.service"];
          };
        };
      };
    };
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
