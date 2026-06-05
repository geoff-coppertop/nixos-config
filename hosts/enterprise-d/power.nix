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
      IdleActionSec = "30s";
      # PNP0C0D emits a spurious lid-open ACPI event when the system briefly
      # wakes from s2idle to write the hibernate image (RTC alarm at
      # HibernateDelaySec). Extending the holdoff window to 60s ensures logind
      # ignores that event on the intermediate wakeup, allowing S4 to complete.
      HoldoffTimeoutSec = "60s";
    };
    power-profiles-daemon.enable = true;
  };
  systemd.sleep.settings.Sleep = {
    HibernateDelaySec = "10min";
  };
  # Three classes of spurious wakeup on this hardware:
  #
  # 1. s2idle phase of suspend-then-hibernate:
  #    PNP0C0D:00 (ACPI lid on EC0) emits phantom events while the lid sits
  #    open, causing systemd's wakeup-source check to treat the s2idle wake as
  #    user-initiated and return to the desktop instead of proceeding to
  #    hibernate.  Disabling this source leaves the RTC timer as the only wake,
  #    so the transition to hibernate reliably fires after HibernateDelaySec.
  #
  # 2. S3 phase of suspend-then-hibernate (USB host controllers):
  #    xHCI controllers fire wake events on phantom USB activity (port polling,
  #    cable handshakes on empty ports, internal device twitches) during S3,
  #    pulling the machine back to the desktop before HibernateDelaySec elapses
  #    so the transition to hibernate never fires.  Affected on this hardware:
  #      c1:00.3  XHC0  - hosts only the Goodix fingerprint reader
  #      c1:00.4  XHC1  - hosts the internal webcam
  #      c3:00.3  XHC3  - empty (external USB-C port)
  #      c3:00.4  XHC4  - empty (external USB-C port)
  #    None of these need to wake the system: the laptop's keyboard/trackpad is
  #    handled by the EC at the ACPI level, not USB, and wake-on-USB-plug from
  #    an empty port is the spurious behaviour we are eliminating.  See:
  #    https://community.frame.work/t/solved-instant-wakeup-from-hibernate-with-linux-6-10-when-bluetooth-is-turned-on-when-xhc0-listens-to-wakeup-events/57044
  #
  # 3. S4 (hibernate) power-off phase:
  #    Five PCI devices are enabled as S4 wakeup sources in the ACPI table and
  #    fire an event the instant the machine enters S4, causing an immediate
  #    resume-from-hibernate rather than a clean power-off:
  #      00:02.2  GPP6  - PCIe root port bridging the Intel AX210 Wi-Fi card
  #      00:03.1  GP11  - USB4/Thunderbolt PCIe tunnel 1
  #      00:04.1  GP12  - USB4/Thunderbolt PCIe tunnel 2
  #      c3:00.5  NHI0  - USB4/Thunderbolt NHI controller #1
  #      c3:00.6  NHI1  - USB4/Thunderbolt NHI controller #2
  #    The machine wakes from S4 via the power button only; disabling these
  #    sources eliminates the instant S4 exit.
  #
  # power/wakeup resets to "enabled" on full resume from S4 (the device is
  # re-initialised at power-on), so the disable is re-asserted after every
  # sleep cycle (After= the sleep targets) as well as at boot (multi-user.target).
  # udev only fires at device-add and does not cover post-resume, hence the
  # service for the re-assertion.
  systemd.services.disable-spurious-wakeup = {
    description = "Disable spurious ACPI/PCI wakeup sources that prevent clean sleep";
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
      ExecStart = pkgs.writeShellScript "disable-spurious-wakeup" ''
        # s2idle: ACPI lid (PNP0C0D) on EC0
        echo disabled > /sys/devices/pci0000:00/0000:00:14.3/PNP0C09:00/PNP0C0D:00/power/wakeup
        # S3: USB host controllers (fingerprint, webcam, empty USB-C ports)
        for dev in 0000:c1:00.3 0000:c1:00.4 0000:c3:00.3 0000:c3:00.4; do
          echo disabled > /sys/bus/pci/devices/$dev/power/wakeup
        done
        # S4: Wi-Fi bridge, USB4/Thunderbolt PCIe tunnels and NHI controllers
        for dev in 0000:00:02.2 0000:00:03.1 0000:00:04.1 0000:c3:00.5 0000:c3:00.6; do
          echo disabled > /sys/bus/pci/devices/$dev/power/wakeup
        done
      '';
    };
  };
  services.udev.extraRules = ''
    # Runtime PM for PCI devices
    ACTION=="add", SUBSYSTEM=="pci", ATTR{power/control}="auto"
    # Runtime PM for USB devices
    ACTION=="add", SUBSYSTEM=="usb", ATTR{power/control}="auto"
    # Disable wakeup at boot for all spurious wakeup sources; re-asserted after
    # every resume by disable-spurious-wakeup.service (see comment above).
    # USB host controllers (S3): fingerprint reader, webcam, empty USB-C ports
    ACTION=="add", SUBSYSTEM=="pci", KERNELS=="0000:c1:00.3", ATTR{power/wakeup}="disabled"
    ACTION=="add", SUBSYSTEM=="pci", KERNELS=="0000:c1:00.4", ATTR{power/wakeup}="disabled"
    ACTION=="add", SUBSYSTEM=="pci", KERNELS=="0000:c3:00.3", ATTR{power/wakeup}="disabled"
    ACTION=="add", SUBSYSTEM=="pci", KERNELS=="0000:c3:00.4", ATTR{power/wakeup}="disabled"
    # PCI bridges (S4): Wi-Fi bridge and Thunderbolt/USB4 devices
    ACTION=="add", SUBSYSTEM=="pci", KERNELS=="0000:00:02.2", ATTR{power/wakeup}="disabled"
    ACTION=="add", SUBSYSTEM=="pci", KERNELS=="0000:00:03.1", ATTR{power/wakeup}="disabled"
    ACTION=="add", SUBSYSTEM=="pci", KERNELS=="0000:00:04.1", ATTR{power/wakeup}="disabled"
    ACTION=="add", SUBSYSTEM=="pci", KERNELS=="0000:c3:00.5", ATTR{power/wakeup}="disabled"
    ACTION=="add", SUBSYSTEM=="pci", KERNELS=="0000:c3:00.6", ATTR{power/wakeup}="disabled"
  '';
}
