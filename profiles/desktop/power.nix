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

  # Exits 0 when any active remote login (SSH) session exists. SSH counts as
  # activity for the suspend chain: someone is working on this machine even
  # when the local graphical session is idle.
  anyRemote = pkgs.writeShellScript "any-remote-session" ''
    for s in $(${pkgs.systemd}/bin/loginctl list-sessions --no-legend 2>/dev/null | ${pkgs.gawk}/bin/awk '{print $1}'); do
      [ "$(${pkgs.systemd}/bin/loginctl show-session "$s" -p Remote --value 2>/dev/null)" = yes ] || continue
      [ "$(${pkgs.systemd}/bin/loginctl show-session "$s" -p State --value 2>/dev/null)" != closing ] && exit 0
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
    user.services = {
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
      idle-hint = {
        description = "Set logind IdleHint via ext-idle-notify on non-GNOME compositors";
        wantedBy = ["graphical-session.target"];
        partOf = ["graphical-session.target"];
        after = ["graphical-session.target"];
        unitConfig = {
          # On a compositor without ext-idle-notify-v1, swayidle exits nonzero
          # and Restart would loop every 10s forever, quietly. Cap it so the
          # unit lands in a visible 'failed' state instead — the signal to
          # check when trying a new DE (test plan section 7).
          StartLimitIntervalSec = "5min";
          StartLimitBurst = 4;
        };
        serviceConfig = {
          Type = "simple";
          Restart = "on-failure";
          RestartSec = "10s";
          # ExecCondition exit 1 = skip cleanly, not a failure. The gdm user's
          # manager is excluded too — systemd.user.services are installed for
          # every user manager including the greeter's, GDM's Mutter also lacks
          # ext-idle-notify-v1, and the greeter gets its IdleHint from the
          # system-level greeter-idle-hint timer below instead.
          ExecCondition = pkgs.writeShellScript "idle-hint-not-gnome" ''
            [ "$(${pkgs.coreutils}/bin/id -un)" = gdm ] && exit 1
            case "''${XDG_CURRENT_DESKTOP:-}" in
              *GNOME*) exit 1 ;;
            esac
          '';
          ExecStart = "${pkgs.swayidle}/bin/swayidle -w idlehint 240";
        };
      };

      # Hold the logind idle inhibitor only while on AC power, allowing
      # logind's IdleAction=suspend to fire after IdleActionSec on battery.
      # One long-lived loop rather than exit-and-restart: the previous design
      # exited immediately on battery and let Restart=always respawn it every
      # 10s, writing Started/Deactivated journal lines for hours — exactly the
      # noise you'd be grepping through when debugging a sleep failure. The
      # active DE's own power manager is disabled from sleeping the system
      # (see the DE's file, e.g. the gsd-power keys in users/thomasga/gnome.nix)
      # so nothing races with logind.
      "logind-idle-inhibitor" = {
        description = "Block logind idle action while on AC power";
        wantedBy = ["graphical-session.target"];
        partOf = ["graphical-session.target"];
        serviceConfig = {
          Type = "simple";
          Restart = "on-failure";
          RestartSec = "10s";
          # The greeter must be allowed to idle-suspend even on AC (login-screen
          # policy is identical on AC and battery — there are no user processes
          # to protect), so this AC inhibitor must never run in the gdm user's
          # manager.
          ExecCondition = pkgs.writeShellScript "inhibitor-not-gdm" ''
            [ "$(${pkgs.coreutils}/bin/id -un)" != gdm ]
          '';
          ExecStart = pkgs.writeShellScript "logind-idle-inhibitor" ''
            while :; do
              if ${onAc}; then
                ${pkgs.systemd}/bin/systemd-inhibit \
                  --what=idle --who=power-manager --why=on-ac-power --mode=block \
                  ${pkgs.bash}/bin/bash -c \
                    'until ! ${onAc}
                     do sleep 5
                     done'
              fi
              sleep 5
            done
          '';
        };
      };
    };

    services = {
      # SSH counts as activity. Two mechanisms are needed because the chain has
      # two independent triggers: this inhibitor blocks logind's IdleAction
      # (which would otherwise fire once a keystroke-quiet SSH session goes
      # idle-by-tty-atime alongside the idle local session), and the
      # battery-idle-suspend watchdog checks for remote sessions itself — it
      # forces suspend with -i, so no inhibitor can stop it. Same quiet-journal
      # loop structure as logind-idle-inhibitor above.
      remote-session-idle-inhibitor = {
        description = "Block logind idle action while remote (SSH) sessions are active";
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Type = "simple";
          Restart = "on-failure";
          RestartSec = "10s";
          ExecStart = pkgs.writeShellScript "remote-session-idle-inhibitor" ''
            while :; do
              if ${anyRemote}; then
                ${pkgs.systemd}/bin/systemd-inhibit \
                  --what=idle --who=remote-sessions --why=active-ssh-session --mode=block \
                  ${pkgs.bash}/bin/bash -c \
                    'while ${anyRemote}
                     do sleep 15
                     done'
              fi
              sleep 15
            done
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
      battery-idle-suspend = {
        description = "Force suspend on battery after sustained idle, overriding inhibitors";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "battery-idle-suspend" ''
            state=/run/battery-idle-suspend-since
            log() {
              ${pkgs.util-linux}/bin/logger -t battery-idle-suspend "$1"
            }

            # Reset branches log only when a countdown was actually in progress
            # (state file exists): the timer fires every minute for hours in
            # steady state, and unconditional logging would drown the journal.
            # This way every countdown start, reset (with reason), and forced
            # suspend is traceable, and quiet runs stay quiet.
            ${onAc} && {
              [ -f "$state" ] && log "countdown reset: back on AC"
              ${pkgs.coreutils}/bin/rm -f "$state"
              exit 0
            }

            session=$(${pkgs.systemd}/bin/loginctl show-seat seat0 -p ActiveSession --value 2>/dev/null)
            [ -n "$session" ] || {
              [ -f "$state" ] && log "countdown reset: no active session"
              ${pkgs.coreutils}/bin/rm -f "$state"
              exit 0
            }

            if [ "$(${pkgs.systemd}/bin/loginctl show-session "$session" -p IdleHint --value 2>/dev/null)" != yes ]; then
              [ -f "$state" ] && log "countdown reset: session active again"
              ${pkgs.coreutils}/bin/rm -f "$state"
              exit 0
            fi

            # SSH counts as activity: never force suspend out from under an
            # active remote session, even though the local session is idle.
            if ${anyRemote}; then
              [ -f "$state" ] && log "countdown reset: remote session active"
              ${pkgs.coreutils}/bin/rm -f "$state"
              exit 0
            fi

            now=$(${pkgs.coreutils}/bin/date +%s)
            [ -f "$state" ] || {
              echo "$now" > "$state"
              log "on battery, session idle, countdown started"
            }
            since=$(${pkgs.coreutils}/bin/cat "$state" 2>/dev/null || echo "$now")
            # The session sets IdleHint=yes at ~240s idle (see the
            # DE-independence contract on the idle-hint unit above); +60s here
            # ~= 300s idle, just past logind's refused ~270s attempt.
            [ $((now - since)) -ge 60 ] || exit 0

            log "on battery, session idle $((now - since))s past hint, forcing suspend -i"
            ${pkgs.coreutils}/bin/rm -f "$state"
            ${pkgs.systemd}/bin/systemctl suspend -i
          '';
        };
      };

      # A greeter-class session (GDM's login screen — or any display manager's;
      # the class is a logind concept, not a GNOME one) never reports idle on
      # its own here: the GDM dconf profile deliberately sets idle-delay=0 to
      # fix resume blanking (profiles/desktop/gnome.nix), which disables the
      # greeter compositor's idle tracking entirely, so the session pins
      # IdleHint=no and blocks logind's IdleAction forever. Nobody "uses" a
      # login screen: an active greeter session is idle by definition. This
      # timer marks it so within ~30s of the greeter becoming the active
      # session; IdleActionSec=30 then suspends ~30s later (never earlier than
      # HoldoffTimeoutSec=60 after boot/resume). Applies on AC and battery
      # alike — with no user logged in there is nothing to protect. Repeated
      # SetIdleHint(yes) calls are no-ops in logind, so the periodic re-run
      # doesn't reset the idle clock.
      greeter-idle-hint = {
        description = "Mark an active greeter session idle so IdleAction can fire";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "greeter-idle-hint" ''
            sid=$(${pkgs.systemd}/bin/loginctl show-seat seat0 -p ActiveSession --value 2>/dev/null)
            [ -n "$sid" ] || exit 0
            [ "$(${pkgs.systemd}/bin/loginctl show-session "$sid" -p Class --value 2>/dev/null)" = greeter ] || exit 0
            [ "$(${pkgs.systemd}/bin/loginctl show-session "$sid" -p IdleHint --value 2>/dev/null)" = yes ] && exit 0
            path=$(${pkgs.systemd}/bin/busctl call org.freedesktop.login1 /org/freedesktop/login1 \
              org.freedesktop.login1.Manager GetSession s "$sid" | ${pkgs.gawk}/bin/awk '{gsub(/"/, ""); print $2}')
            [ -n "$path" ] || exit 0
            ${pkgs.systemd}/bin/busctl call org.freedesktop.login1 "$path" \
              org.freedesktop.login1.Session SetIdleHint b true
            ${pkgs.util-linux}/bin/logger -t greeter-idle-hint "greeter session $sid active, IdleHint set, IdleAction suspend follows in ~30s"
          '';
        };
      };
    };

    timers = {
      battery-idle-suspend = {
        description = "Periodic battery idle-suspend check";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "2min";
          OnUnitActiveSec = "1min";
          AccuracySec = "10s";
        };
      };

      greeter-idle-hint = {
        description = "Periodic greeter idle-hint check";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "30s";
          OnUnitActiveSec = "30s";
          AccuracySec = "5s";
        };
      };
    };
  };
}
