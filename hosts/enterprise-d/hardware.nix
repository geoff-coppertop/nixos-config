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
    # Plymouth needs a framebuffer to draw into before the real root is
    # mounted. Without amdgpu loaded this early, KMS doesn't happen until
    # normal module loading kicks in well after Plymouth has already tried
    # (and failed, silently — black screen, no error) to render.
    initrd.kernelModules = ["amdgpu"];
  };
  services.xserver.videoDrivers = ["amdgpu"];
  hardware = {
    cpu.amd.updateMicrocode = true;
    enableRedistributableFirmware = true;
  };
  services.fwupd.enable = true;
}
