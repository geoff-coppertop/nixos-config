{pkgs, ...}: {
  boot = {
    kernelParams = [
      "mem_sleep_default=s2idle"
      "button.lid_init_state=open"
      "amd_pstate=active"
      # Switches RTC wakeup to ACPI alarms instead of HPET, avoiding an
      # AMD EC/RTC timing race (rtc->aie_timer mismatch in amd-pmc's
      # timer-based S0i3 wakeup handling) that otherwise causes the
      # suspend-then-hibernate RTC alarm to be misread as a user wake.
      "rtc_cmos.use_acpi_alarm=1"
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
      HoldoffTimeoutSec = "60s";
    };
    power-profiles-daemon.enable = true;
  };
  systemd = {
    sleep.settings.Sleep = {
      HibernateDelaySec = "10min";
    };
    # Permanent diagnostic logging for both suspend-then-hibernate trigger
    # paths (HandleLidSwitch and IdleAction both route through this unit).
    # Left in place indefinitely so any spurious-wake or non-hibernate cycle
    # is visible in `journalctl -t hibernate-trigger` without needing extra
    # workarounds re-added blind.
    #
    # Hibernation detection greps this unit's own log (since this cycle's
    # start) for systemd-sleep's "Attempting to hibernate" line. A prior
    # version compared the kernel boot ID before/after, on the assumption
    # that a real hibernate cycle resumes into a fresh boot — that's wrong:
    # hibernate resume restores the original kernel's in-memory state
    # (including boot_id) rather than booting a new one, so the boot ID
    # never changes even on a genuine hibernate, making that check always
    # report `hibernated: no`. Confirmed wrong by a real cycle whose
    # systemd-sleep log showed "Attempting to hibernate" / "Using sleep
    # state 'disk'" while the boot-ID check still said "no".
    # Temporary diagnostic only: surfaces systemd-sleep's internal
    # woken_by_timer/timerfd decision (custom_timer_suspend() in
    # src/sleep/sleep.c), which is silent at the default log level. Needed
    # to confirm whether failed suspend-then-hibernate cycles match the
    # known upstream zero-timeout POLLIN race (systemd/systemd#38193)
    # before deciding on a fix. Remove once that's confirmed either way.
    services.systemd-suspend-then-hibernate = {
      environment = {
        SYSTEMD_LOG_LEVEL = "debug";
      };
      serviceConfig = {
        ExecStartPre = [
          (pkgs.writeShellScript "hibernate-trigger-pre" ''
            ${pkgs.coreutils}/bin/date +%s > /run/hibernate-trigger-start
            ${pkgs.util-linux}/bin/logger -t hibernate-trigger "suspend-then-hibernate starting at $(${pkgs.coreutils}/bin/date +%s)"
          '')
        ];
        ExecStartPost = [
          (pkgs.writeShellScript "hibernate-trigger-post" ''
            now=$(${pkgs.coreutils}/bin/date +%s)
            start=$(${pkgs.coreutils}/bin/cat /run/hibernate-trigger-start 2>/dev/null || echo "$now")
            if ${pkgs.systemd}/bin/journalctl -u systemd-suspend-then-hibernate.service --since "@$start" \
                | ${pkgs.gnugrep}/bin/grep -q "Attempting to hibernate"; then
              hibernated=yes
            else
              hibernated=no
            fi
            ${pkgs.util-linux}/bin/logger -t hibernate-trigger "resumed at $now, hibernated: $hibernated"
          '')
        ];
      };
    };
  };
}
