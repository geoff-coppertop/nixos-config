{
  boot = {
    loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = 10;
      };
      efi.canTouchEfiVariables = true;
    };
    initrd.systemd.enable = true;
  };
  services.xserver.videoDrivers = ["amdgpu"];
  hardware = {
    cpu.amd.updateMicrocode = true;
    enableRedistributableFirmware = true;
  };
  services.fwupd.enable = true;
}
