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
      HandleLidSwitchExternalPower = "lock";
      HandleLidSwitchDocked = "ignore";
      HandleHibernateKey = "hibernate";
      IdleAction = "suspend-then-hibernate";
      # Fires 1 min after GNOME blanks the screen (idle-delay = 4 min), so ~5 min from last input
      IdleActionSec = "1min";
    };
    power-profiles-daemon.enable = true;
  };
  systemd.sleep.settings.Sleep = {
    HibernateDelaySec = "10min";
  };
  services.udev.extraRules = ''
    # Runtime PM for PCI devices
    ACTION=="add", SUBSYSTEM=="pci", ATTR{power/control}="auto"
    # Runtime PM for USB devices
    ACTION=="add", SUBSYSTEM=="usb", ATTR{power/control}="auto"
    # XHC0 (pci 0000:c1:00.3) hosts only the Goodix fingerprint reader and causes
    # an immediate spurious wakeup from suspend on the Framework 13 AMD. Disabling
    # its wakeup allows suspend-then-hibernate to complete normally. Keyboard,
    # trackpad, and other input devices are on separate controllers and are unaffected.
    # The linked thread documents the same symptom (XHC0 causing instant wakeup) and
    # fix on the same hardware; in that case the trigger was Bluetooth rather than
    # the fingerprint reader, but the affected controller and solution are identical.
    # https://community.frame.work/t/solved-instant-wakeup-from-hibernate-with-linux-6-10-when-bluetooth-is-turned-on-when-xhc0-listens-to-wakeup-events/57044
    ACTION=="add", SUBSYSTEM=="pci", KERNELS=="0000:c1:00.3", ATTR{power/wakeup}="disabled"
  '';
}
