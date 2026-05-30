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
  # The ACPI lid device (PNP0C0D, hanging off the EC0 embedded controller)
  # emits phantom wakeup events while the machine sits idle with the lid open.
  # During suspend-then-hibernate those events make systemd's wakeup-source
  # check conclude the user woke the machine, so it returns from the s2idle
  # phase instead of advancing to hibernate (and sometimes wakes seconds in).
  # Disabling the lid as a wakeup source leaves the RTC timer as the sole wake
  # during suspend, so suspend-then-hibernate reliably reaches hibernate.
  # Keyboard, trackpad, and the power button are on separate controllers and
  # still wake the machine; only "open the lid to wake" is given up, which is
  # moot here since the laptop idles with the lid open.
  #
  # power/wakeup can come back enabled after a resume (observed at least once
  # on this hardware), so the disable is re-asserted on the resume side of each
  # sleep cycle (After= the sleep targets) as well as at boot (multi-user.target).
  # This is the ACPI sibling of the XHC0 udev rule below; udev only fires at
  # device-add, which would not survive a resume, hence a service instead.
  systemd.services.disable-lid-wakeup = {
    description = "Disable spurious lid ACPI wakeup (PNP0C0D) so suspend-then-hibernate completes";
    wantedBy = [
      "multi-user.target"
      "suspend.target"
      "hibernate.target"
      "suspend-then-hibernate.target"
      "hybrid-sleep.target"
    ];
    after = [
      "suspend.target"
      "hibernate.target"
      "suspend-then-hibernate.target"
      "hybrid-sleep.target"
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -c 'echo disabled > /sys/devices/pci0000:00/0000:00:14.3/PNP0C09:00/PNP0C0D:00/power/wakeup'";
    };
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
