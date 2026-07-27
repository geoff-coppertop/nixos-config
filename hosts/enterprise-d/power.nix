{
  config,
  lib,
  pkgs,
  ...
}: {
  # Fail the build, not the 2%-battery moment, if the hibernate target
  # drifts: the RTC hibernate chain is only sound while resumeDevice points
  # at a configured swap device. /dev/vg/swap and /dev/mapper/vg-swap are
  # the same LV under two names; compare normalised.
  assertions = let
    normalise = lib.replaceStrings ["/dev/mapper/vg-"] ["/dev/vg/"];
    resume = config.boot.resumeDevice;
  in [
    {
      assertion = resume != "";
      message = "hibernate-trigger requires boot.resumeDevice to be set";
    }
    {
      assertion = builtins.any (d: normalise d.device == normalise resume) config.swapDevices;
      message = "boot.resumeDevice (${resume}) is not among swapDevices — hibernate has nowhere to write its image";
    }
  ];

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
  systemd.services = {
    hibernate-trigger-hibernate = {
      description = "Hibernate after an RTC-wakealarm-triggered resume";
      after = ["systemd-suspend.service"];
      # A failed hibernate (swap pressure, transient kernel error) would
      # otherwise leave the machine awake and draining at the lock screen —
      # the exact outcome this machinery exists to prevent — reported only as
      # a quiet unit failure. The fallback re-suspends instead; that re-runs
      # the sleep hook and re-arms the RTC alarm, so a failed hibernate
      # becomes a retry-every-10-min loop (asleep between attempts, every
      # attempt logged) rather than hours awake.
      onFailure = ["hibernate-trigger-fallback.service"];
      serviceConfig = {
        Type = "oneshot";
        # -i (ignore-inhibitors): the app suspend-inhibitor that the watchdog
        # forces past with `suspend -i` is still held on the RTC-wake resume, so a
        # plain `systemctl hibernate` is refused and the machine just stays awake.
        # Root is authorised non-interactively for hibernate-ignore-inhibit by the
        # polkit rule in profiles/desktop/power.nix — mirrors the suspend path.
        ExecStart = "${pkgs.systemd}/bin/systemctl hibernate -i";
      };
    };

    hibernate-trigger-fallback = {
      description = "Re-suspend after a failed RTC-triggered hibernate";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "hibernate-trigger-fallback" ''
          ${pkgs.util-linux}/bin/logger -t hibernate-trigger "hibernate FAILED, re-suspending to retry via the RTC cycle"
          ${pkgs.systemd}/bin/systemctl suspend -i
        '';
      };
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
      log() {
        ${pkgs.util-linux}/bin/logger -t hibernate-trigger "$1"
      }

      [ "$sleep_action" = suspend ] || exit 0

      case "$action" in
        pre)
          now=$(${pkgs.coreutils}/bin/date +%s)
          wake_at=$((now + delay_sec))
          # Clear any leftover alarm first: the sysfs interface rejects a new
          # value while one is armed, so a stale alarm (e.g. crash between pre
          # and post) would otherwise make this arm fail.
          echo 0 > "$wakealarm" 2>/dev/null || true
          # Verify the arm and record the outcome in the state file. Without
          # this, a silently failed arm leaves the machine suspended until a
          # real user wake hours later — whose huge elapsed time the post
          # branch would misread as the timer firing, force-hibernating the
          # machine right as the user resumes it.
          if echo "$wake_at" > "$wakealarm" 2>/dev/null; then
            echo "$now armed" > "$state_file"
            log "suspend starting at $now, wakealarm armed for $wake_at (+''${delay_sec}s)"
          else
            echo "$now failed" > "$state_file"
            log "suspend starting at $now, FAILED to arm wakealarm, timed hibernate disabled for this cycle"
          fi
          ;;
        post)
          now=$(${pkgs.coreutils}/bin/date +%s)
          start=""
          armed=""
          [ -f "$state_file" ] && read -r start armed < "$state_file"
          [ -n "$start" ] || start=$now
          elapsed=$((now - start))
          echo 0 > "$wakealarm" 2>/dev/null || true
          if [ "$armed" != armed ]; then
            log "resumed at $now, elapsed=''${elapsed}s, wakealarm was never armed, not hibernating"
          elif [ "$elapsed" -ge $((delay_sec - 5)) ]; then
            log "resumed at $now, elapsed=''${elapsed}s, triggering hibernate"
            ${pkgs.systemd}/bin/systemctl start --no-block hibernate-trigger-hibernate.service
          else
            log "resumed at $now, elapsed=''${elapsed}s, early wake, no hibernate"
          fi
          ;;
      esac
    '';
  };
}
