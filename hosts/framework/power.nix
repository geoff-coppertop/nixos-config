{pkgs, ...}: {
  boot = {
    kernelParams = [
      "mem_sleep_default=s2idle"
      "button.lid_init_state=open"
      "amd_pstate=active"
    ];
    resumeDevice = "/dev/vg/swap";
  };
  environment.systemPackages = with pkgs; [
    powertop
    lm_sensors
  ];
  networking.networkmanager.wifi.powersave = true;
  services = {
    logind.settings.Login = {
      HandleLidSwitch = "suspend-then-hibernate";
      HandleLidSwitchExternalPower = "suspend-then-hibernate";
      HandleLidSwitchDocked = "ignore";
      HandleHibernateKey = "hibernate";
      IdleAction = "suspend-then-hibernate";
      IdleActionSec = "30s";
    };
    power-profiles-daemon.enable = true;
  };
  systemd.sleep.settings.Sleep = {
    HibernateDelaySec = "9min 30s";
  };
  services.udev.extraRules = ''
    # Runtime PM for PCI devices
    ACTION=="add", SUBSYSTEM=="pci", ATTR{power/control}="auto"
    # Runtime PM for USB devices
    ACTION=="add", SUBSYSTEM=="usb", ATTR{power/control}="auto"
  '';
}
