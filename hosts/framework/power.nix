{pkgs, ...}: {
  boot.kernelParams = [
    "amd_pstate=active"
    "mem_sleep_default=s2idle"
    "resume=/dev/disk/by-partlabel/swap"

    "amdgpu.dc=1"
    "amdgpu.runpm=1"
    "amdgpu.dpm=1"
    "amdgpu.dcdebugmask=0x10"

    "nvme.noacpi=1"
  ];

  environment.systemPackages = with pkgs; [
    powertop
    lm_sensors
  ];

  networking.networkmanager.wifi.powersave = true;

  powerManagement = {
    cpuFreqGovernor = "powersave";
    powertop.enable = true;
  };

  services = {
    power-profiles-daemon.enable = true;

    udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="pci", TEST=="power/control", ATTR{power/control}="auto"
      ACTION=="add", SUBSYSTEM=="usb", TEST=="power/control", ATTR{power/control}="auto"
    '';

    logind = {
      # REMOVED: legacy lidSwitch attributes
      settings = {
        Login = {
          HandleLidSwitch = "suspend";
          HandleLidSwitchExternalPower = "ignore";
          HandleLidSwitchDocked = "ignore"; # Added this here
          HandleHibernateKey = "hibernate";
        };
      };
    };

    auto-cpufreq.enable = false;
    tlp.enable = false;
  };
}
