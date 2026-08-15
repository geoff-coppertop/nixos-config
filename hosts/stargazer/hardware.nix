{
  boot = {
    loader = {
      # secureBoot (lanzaboote) force-disables systemd-boot; this stays as the
      # pre-Secure-Boot fallback, mirroring enterprise-d.
      systemd-boot = {
        enable = true;
        configurationLimit = 10;
      };
      efi.canTouchEfiVariables = true;
    };
    initrd = {
      systemd.enable = true;
      availableKernelModules = ["nvme" "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod"];
    };
  };

  hardware = {
    # Ryzen 5800X3D.
    cpu.amd.updateMicrocode = true;
    enableRedistributableFirmware = true;
  };

  services.fwupd.enable = true;
}
