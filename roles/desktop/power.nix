{pkgs, ...}: let
  # Exits 0 when running on AC, 1 when on battery. Only Mains-type supplies
  # count: the Framework's USB-C PD source ports (ucsi-source-psy-*, type
  # "USB") can read online=1 on battery while sourcing power to a peripheral,
  # so a bare /sys/class/power_supply/*/online glob false-positives.
  onAc = pkgs.writeShellScript "on-ac-power" ''
    for t in /sys/class/power_supply/*/type; do
      [ "$(${pkgs.coreutils}/bin/cat "$t" 2>/dev/null)" = Mains ] || continue
      read -r online < "''${t%type}online" 2>/dev/null || continue
      [ "$online" = 1 ] && exit 0
    done
    exit 1
  '';
in {
  # The root battery-idle-suspend watchdog below forces `systemctl suspend -i`
  # past a block-mode application inhibitor. That override is gated by the polkit
  # action suspend-ignore-inhibit, whose default requires interactive admin auth
  # even for root (polkit does not implicitly authorise uid 0). A non-interactive
  # system service has no polkit agent, so without this rule the request is
  # denied silently. Grant it for root only; the interactive user is unaffected.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if ((action.id == "org.freedesktop.login1.suspend-ignore-inhibit" ||
           action.id == "org.freedesktop.login1.hibernate-ignore-inhibit") &&
          subject.user == "root") {
        return polkit.Result.YES;
      }
    });
  '';

  # Critical-battery hibernate is owned by UPower, not the DE. The upower
  # daemon performs CriticalPowerAction itself (via logind) when the battery
  # reaches percentageAction, so this works identically under any
  # desktop/compositor. Thresholds are the upstream defaults, made explicit
  # because they are policy this host relies on.
  services.upower = {
    enable = true;
    usePercentageForPolicy = true;
    percentageLow = 10;
    percentageCritical = 3;
    percentageAction = 2;
    criticalPowerAction = "Hibernate";
  };

  systemd = {
    # DE-independence contract: everything downstream — logind's
    # IdleAction=suspend at +30s, the battery-idle-suspend watchdog at +60s,
    # the suspend->hibernate RTC chain — keys off the logind session
    # IdleHint. The only thing the active session must provide is setting
    # IdleHint=yes at ~240s of user inactivity. GNOME/Mutter does that
    # natively at its idle-delay (users/thomasga/gnome.nix, 240s) and does
    # not implement ext-idle-notify-v1, so this unit skips itself there.
    # Any compositor that does implement ext-idle-notify-v1 (COSMIC,
    # Hyprland, sway, ...) is covered by swayidle instead. Keep the timeout
    # in sync with GNOME's 240s idle-delay so the suspend chain behaves the
    # same regardless of DE.
    user.services.idle-hint = {
      description = "Set logind IdleHint via ext-idle-notify on non-GNOME compositors";
      wantedBy = ["graphical-session.target"];
      partOf = ["graphical-session.target"];
      after = ["graphical-session.target"];
      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = "10s";
        # ExecCondition exit 1 = skip cleanly, not a failure.
        ExecCondition = pkgs.writeShellScript "idle-hint-not-gnome" ''
          case "''${XDG_CURRENT_DESKTOP:-}" in
            *GNOME*) exit 1 ;;
          esac
        '';
        ExecStart = "${pkgs.swayidle}/bin/swayidle -w idlehint 240";
      };
    };

    # Hold the logind idle inhibitor only while on AC power.
    # On battery the service exits immediately (no inhibitor held), allowing
    # logind's IdleAction=suspend to fire after IdleActionSec. On AC the
    # inhibitor is held and the inner loop monitors power state, exiting when AC
    # is disconnected so the service restarts and re-evaluates. The active DE's
    # own power manager is disabled from sleeping the system (see the DE's
    # file, e.g. the gsd-power keys in users/thomasga/gnome.nix) so nothing
    # races with logind.
    user.services."logind-idle-inhibitor" = {
      description = "Block logind idle action while on AC power";
      wantedBy = ["graphical-session.target"];
      partOf = ["graphical-session.target"];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "10s";
        ExecStart = pkgs.writeShellScript "logind-idle-inhibitor" ''
          ${onAc} || exit 0
          exec ${pkgs.systemd}/bin/systemd-inhibit \
            --what=idle --who=power-manager --why=on-ac-power --mode=block \
            ${pkgs.bash}/bin/bash -c \
              'until ! ${onAc}
               do sleep 5
               done'
        '';
      };
    };

    # Force suspend on battery after sustained idle, overriding application
    # inhibitors. An app holding a block-mode sleep inhibitor (e.g. a browser
    # "Playing video" inhibit, relayed by the DE's session manager) otherwise
    # makes logind refuse the idle suspend forever, draining the battery.
    # Policy: on battery, sustained idle wins even if it interrupts a
    # background task.
    #
    # logind's own IdleAction fires at ~270s (IdleHint at 240 + IdleActionSec 30)
    # and handles the uninhibited case; this watchdog reaches its threshold only
    # when that suspend was refused, then forces it with `suspend -i` (authorised
    # for root by the polkit rule above). Idle duration is measured by how long
    # the session's IdleHint has continuously been "yes", timed with a /run state
    # file and wall-clock `date +%s` — never by subtracting logind's
    # CLOCK_MONOTONIC IdleSinceHint from CLOCK_BOOTTIME /proc/uptime, which would
    # double-count every second spent suspended. `systemctl suspend` still runs
    # the hibernate-trigger system-sleep hook, preserving suspend->hibernate-10min.
    services.battery-idle-suspend = {
      description = "Force suspend on battery after sustained idle, overriding inhibitors";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "battery-idle-suspend" ''
          state=/run/battery-idle-suspend-since

          ${onAc} && {
            ${pkgs.coreutils}/bin/rm -f "$state"
            exit 0
          }

          session=$(${pkgs.systemd}/bin/loginctl show-seat seat0 -p ActiveSession --value 2>/dev/null)
          [ -n "$session" ] || {
            ${pkgs.coreutils}/bin/rm -f "$state"
            exit 0
          }

          if [ "$(${pkgs.systemd}/bin/loginctl show-session "$session" -p IdleHint --value 2>/dev/null)" != yes ]; then
            ${pkgs.coreutils}/bin/rm -f "$state"
            exit 0
          fi

          now=$(${pkgs.coreutils}/bin/date +%s)
          [ -f "$state" ] || echo "$now" > "$state"
          since=$(${pkgs.coreutils}/bin/cat "$state" 2>/dev/null || echo "$now")
          # The session sets IdleHint=yes at ~240s idle (see the
          # DE-independence contract on the idle-hint unit above); +60s here
          # ~= 300s idle, just past logind's refused ~270s attempt.
          [ $((now - since)) -ge 60 ] || exit 0

          ${pkgs.util-linux}/bin/logger -t battery-idle-suspend "on battery, session idle, forcing suspend -i"
          ${pkgs.coreutils}/bin/rm -f "$state"
          ${pkgs.systemd}/bin/systemctl suspend -i
        '';
      };
    };

    timers.battery-idle-suspend = {
      description = "Periodic battery idle-suspend check";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "1min";
        AccuracySec = "10s";
      };
    };
  };
}
