{pkgs, ...}: {
  boot = {
    kernelParams = [
      "amd_pstate=active"
      "mem_sleep_default=s2idle"
      "amdgpu.dc=1"
      "amdgpu.runpm=1"
      "amdgpu.dpm=1"
      "nvme.noacpi=1"
    ];
    resumeDevice = "/dev/vg/swap";
  };
  environment.systemPackages = with pkgs; [
    powertop
    lm_sensors
  ];
  networking.networkmanager.wifi.powersave = true;
  powerManagement = {
    cpuFreqGovernor = "powersave";
  };
  services = {
    power-profiles-daemon.enable = true;
    udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="pci", TEST=="power/control", ATTR{power/control}="auto"
      ACTION=="add", SUBSYSTEM=="usb", TEST=="power/control", ATTR{power/control}="auto"
    '';
    logind.settings.Login = {
      HandleLidSwitch = "suspend";
      HandleLidSwitchExternalPower = "ignore";
      HandleLidSwitchDocked = "ignore";
      HandleHibernateKey = "hibernate";
    };
  };
}
