{
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    initrd = {
      kernelModules = ["amdgpu"];
      systemd.enable = true;
    };
  };
  services.xserver.videoDrivers = ["amdgpu"];
  hardware = {
    cpu.amd.updateMicrocode = true;
    enableRedistributableFirmware = true;
  };
}
