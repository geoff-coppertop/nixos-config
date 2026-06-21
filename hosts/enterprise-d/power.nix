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
      # Plain suspend, not suspend-then-hibernate: systemd's own
      # suspend-then-hibernate logic (execute_s2h()/custom_timer_suspend()
      # in src/sleep/sleep.c) has a zero-timeout POLLIN race where the
      # RTC/EC timer wake reaches the process before systemd's own poll on
      # the timerfd reports readable, so it treats the wake as
      # user-initiated and skips hibernate (systemd/systemd#38193, open,
      # unfixed). Measured ~43% failure rate on this hardware across 7 real
      # cycles even with rtc_cmos.use_acpi_alarm=1 set above, because that
      # param only affects how the RTC alarm is routed at the kernel/EC
      # layer — it doesn't touch systemd's own racy poll logic. The
      # hibernate-trigger system-sleep hook below replaces systemd's timer
      # decision with our own non-racy wall-clock check.
      HandleLidSwitch = "suspend";
      HandleLidSwitchExternalPower = "lock";
      HandleLidSwitchDocked = "ignore";
      HandleHibernateKey = "hibernate";
      IdleAction = "suspend";
      IdleActionSec = "30s";
      HoldoffTimeoutSec = "60s";
    };
    power-profiles-daemon.enable = true;
  };
  # logind treats a sleep operation as in-progress until the job for
  # systemd-suspend.service itself completes, which doesn't happen until
  # this hook (run from inside that job's ExecStart) returns. Ordering
  # this unit's job After= that service, rather than calling `systemctl
  # hibernate` inline, lets systemd's own job scheduler defer it until
  # the suspend job actually finishes and the lock clears — no polling,
  # no fixed delay.
  systemd.services.hibernate-trigger-hibernate = {
    description = "Hibernate after an RTC-wakealarm-triggered resume";
    after = ["systemd-suspend.service"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemctl hibernate";
    };
  };
  # Arms the RTC wakealarm directly on suspend and decides on resume,
  # using wall-clock elapsed time, whether to hibernate. Both HandleLidSwitch
  # and IdleAction route through stock systemd-suspend.service, so this one
  # hook covers both trigger paths. Permanent logging tagged
  # `hibernate-trigger`, left in place indefinitely (see journalctl -t
  # hibernate-trigger).
  environment.etc."systemd/system-sleep/hibernate-trigger" = {
    mode = "0755";
    source = pkgs.writeShellScript "hibernate-trigger" ''
      action="$1"
      sleep_action="$2"
      delay_sec=600
      state_file=/run/hibernate-trigger-start
      wakealarm=/sys/class/rtc/rtc0/wakealarm

      [ "$sleep_action" = suspend ] || exit 0

      case "$action" in
        pre)
          now=$(${pkgs.coreutils}/bin/date +%s)
          echo "$now" > "$state_file"
          wake_at=$((now + delay_sec))
          echo "$wake_at" > "$wakealarm" 2>/dev/null || true
          ${pkgs.util-linux}/bin/logger -t hibernate-trigger "suspend starting at $now, wakealarm armed for $wake_at (+''${delay_sec}s)"
          ;;
        post)
          now=$(${pkgs.coreutils}/bin/date +%s)
          start=$(${pkgs.coreutils}/bin/cat "$state_file" 2>/dev/null || echo "$now")
          elapsed=$((now - start))
          echo 0 > "$wakealarm" 2>/dev/null || true
          if [ "$elapsed" -ge $((delay_sec - 5)) ]; then
            ${pkgs.util-linux}/bin/logger -t hibernate-trigger "resumed at $now, elapsed=''${elapsed}s, triggering hibernate"
            ${pkgs.systemd}/bin/systemctl start --no-block hibernate-trigger-hibernate.service
          else
            ${pkgs.util-linux}/bin/logger -t hibernate-trigger "resumed at $now, elapsed=''${elapsed}s, early wake, no hibernate"
          fi
          ;;
      esac
    '';
  };
}
