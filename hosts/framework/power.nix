{ pkgs, ... }:

{
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

  powerManagement.cpuFreqGovernor = "powersave";

  services.power-profiles-daemon.enable = true;

  services.powertop = {
    enable = true;
    autoTune = true;
  };

  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="pci", TEST=="power/control", ATTR{power/control}="auto"
    ACTION=="add", SUBSYSTEM=="usb", TEST=="power/control", ATTR{power/control}="auto"
  '';

  networking.networkmanager.wifi.powersave = true;

  services.logind = {
    lidSwitch = "suspend";
    lidSwitchExternalPower = "ignore";
    lidSwitchDocked = "ignore";
    extraConfig = ''
      HandleHibernateKey=hibernate
    '';
  };

  services.auto-cpufreq.enable = false;
  services.tlp.enable = false;

  environment.systemPackages = with pkgs; [
    powertop
    lm_sensors
  ];
}
