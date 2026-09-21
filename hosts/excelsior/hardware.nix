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

    # sg (classic SCSI generic passthrough) isn't loaded by default; only
    # bsg (the newer block-layer interface) is. Confirmed live: MakeMKV
    # needs a real /dev/sg* node for Blu-ray ripping (custom.autoRip
    # passes it in via extraDevices) and fails with "Failed to open disc"
    # against /dev/sr0 alone.
    kernelModules = ["sg"];
  };

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;
}
