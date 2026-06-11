{pkgs, ...}: {
  # Hold the logind idle inhibitor only while on AC power.
  # On battery the service exits immediately (no inhibitor held), allowing
  # logind's IdleAction=suspend-then-hibernate to fire after IdleActionSec.
  # On AC the inhibitor is held and the inner loop monitors power state,
  # exiting when AC is disconnected so the service restarts and re-evaluates.
  # gsd-power's sleep-inactive-battery-type is set to "nothing" so it does
  # not race with logind's idle action on battery.
  systemd.user.services."logind-idle-inhibitor" = {
    description = "Block logind idle action while on AC power";
    wantedBy = ["graphical-session.target"];
    partOf = ["graphical-session.target"];
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = "10s";
      ExecStart = pkgs.writeShellScript "logind-idle-inhibitor" ''
        grep -q '^1$' /sys/class/power_supply/*/online 2>/dev/null || exit 0
        exec ${pkgs.systemd}/bin/systemd-inhibit \
          --what=idle --who=power-manager --why=on-ac-power --mode=block \
          ${pkgs.bash}/bin/bash -c \
            'until ! grep -q "^1$" /sys/class/power_supply/*/online 2>/dev/null
             do sleep 5
             done'
      '';
    };
  };
}
