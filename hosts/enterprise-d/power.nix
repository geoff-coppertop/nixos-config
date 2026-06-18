{
  pkgs,
  lib,
  ...
}: let
  # Patch systemd to fix a race in execute_s2h(): on AMD platforms the RTC alarm
  # routes through the EC (GPE 0x0B / IRQ 9), which wakes s2idle before the
  # timerfd POLLIN callback fires.  fd_wait_for_event(tfd, POLLIN, 0) with a
  # zero timeout returns 0, so systemd treats the wake as manual and skips
  # hibernate.  The fallback checks CLOCK_BOOTTIME directly, which is
  # race-free.
  #
  # Built separately from the system systemd to avoid re-linking the ~600
  # packages that depend on it; only the ExecStart of the service unit changes.
  patchedSystemd = pkgs.systemd.overrideAttrs (old: {
    patches = (old.patches or []) ++ [../../patches/systemd-s2h-boottime-fallback.patch];
  });
in {
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
  systemd = {
    sleep.settings.Sleep = {
      HibernateDelaySec = "10min";
    };
    services = {
      # Four classes of spurious wakeup on this hardware that prevent
      # suspend-then-hibernate from reaching the hibernate step:
      #
      # 1. s2idle — ACPI EC battery/AC notifications:
      #    The EC (PNP0C09) fires GPE 0x0B (ACPI SCI, IRQ 9) for any EC event
      #    including periodic battery capacity updates and AC adapter state
      #    notifications.  These wake s2idle before HibernateDelaySec elapses;
      #    since the timerfd hasn't fired, execute_s2h() treats the wake as
      #    user-initiated and returns to the desktop.
      #      PNP0C0A:00  — ACPI battery (fires as battery discharges)
      #      ACAD        — ACPI AC adapter (fires on plug/unplug)
      #    The hardware battery trip-point alarm (BAT1/alarm, ~34%) routes
      #    through a separate EC mechanism and is unaffected.
      #
      # 2. s2idle — ACPI lid (PNP0C0D):
      #    PNP0C0D:00 emits phantom open events while the lid sits open,
      #    causing execute_s2h() to treat each wake as user-initiated.
      #
      # 3. S3 — USB host controllers:
      #    xHCI controllers fire on phantom USB activity during S3, waking
      #    the machine before HibernateDelaySec elapses.
      #      c1:00.3  XHC0 — Goodix fingerprint reader
      #      c1:00.4  XHC1 — internal webcam
      #      c3:00.3  XHC3 — empty USB-C port
      #      c3:00.4  XHC4 — empty USB-C port
      #    See: https://community.frame.work/t/solved-instant-wakeup-from-hibernate-with-linux-6-10-when-bluetooth-is-turned-on-when-xhc0-listens-to-wakeup-events/57044
      #
      # 4. S4 — PCI bridges:
      #    Five PCI devices fire the instant the machine enters S4, causing an
      #    immediate resume-from-hibernate instead of a clean power-off.
      #      00:02.2  GPP6 — PCIe root port for Intel AX210 Wi-Fi
      #      00:03.1  GP11 — USB4/Thunderbolt PCIe tunnel 1
      #      00:04.1  GP12 — USB4/Thunderbolt PCIe tunnel 2
      #      c3:00.5  NHI0 — USB4/Thunderbolt NHI controller 1
      #      c3:00.6  NHI1 — USB4/Thunderbolt NHI controller 2
      #
      # power/wakeup resets to "enabled" on full resume from S4, so the
      # disable is re-asserted after every sleep cycle (After= the sleep
      # targets) as well as at boot (multi-user.target).  udev covers
      # device-add but not post-resume, hence this service.
      disable-spurious-wakeup = {
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
            # s2idle: ACPI battery and AC adapter notifications via EC (GPE 0x0B)
            echo disabled > /sys/devices/pci0000:00/0000:00:14.3/PNP0C0A:00/power/wakeup
            echo disabled > /sys/devices/pci0000:00/0000:00:14.3/ACPI0003:00/power_supply/ACAD/power/wakeup
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

      # Log wakeup source after each sleep cycle for diagnosis.
      log-sleep-wakeup = {
        description = "Log wakeup source after sleep";
        wantedBy = [
          "suspend.target"
          "hibernate.target"
          "suspend-then-hibernate.target"
        ];
        after = [
          "suspend.target"
          "hibernate.target"
          "suspend-then-hibernate.target"
        ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "log-sleep-wakeup" ''
            ${pkgs.util-linux}/bin/logger -t sleep-wakeup "pm_wakeup_timestamp: $(cat /sys/power/pm_wakeup_timestamp 2>/dev/null)"
            ${pkgs.util-linux}/bin/logger -t sleep-wakeup "IRQ 9 count: $(awk '/^ *9:/{print $2}' /proc/interrupts 2>/dev/null)"
            ${pkgs.util-linux}/bin/logger -t sleep-wakeup "IRQ 9 spurious: $(cat /sys/kernel/irq/9/spurious 2>/dev/null)"
          '';
        };
      };

      # Use the patched systemd-sleep binary (CLOCK_BOOTTIME fallback fix).
      # SYSTEMD_LOG_LEVEL=debug is intentionally left on to diagnose the
      # execute_s2h() / custom_timer_suspend() decision path.
      "systemd-suspend-then-hibernate" = {
        serviceConfig = {
          ExecStart = lib.mkForce [
            ""
            "${patchedSystemd}/lib/systemd/systemd-sleep suspend-then-hibernate"
          ];
          Environment = "SYSTEMD_LOG_LEVEL=debug";
        };
      };
    };
  };
  services.udev.extraRules = ''
    # Runtime PM for PCI devices
    ACTION=="add", SUBSYSTEM=="pci", ATTR{power/control}="auto"
    # Runtime PM for USB devices
    ACTION=="add", SUBSYSTEM=="usb", ATTR{power/control}="auto"
    # Disable wakeup at boot for spurious sources; re-asserted after every
    # resume by disable-spurious-wakeup.service (see comment above).
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
