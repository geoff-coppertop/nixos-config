{
  config,
  pkgs,
  ...
}: let
  powerprofilesctl = "${config.services.power-profiles-daemon.package}/bin/powerprofilesctl";
  logger = "${pkgs.util-linux}/bin/logger";

  # Panel power savings (amdgpu ABM) is 0-4; 3 avoids the colour shift of 4.
  # The write is refused with EBUSY if a compositor has claimed ABM control.
  policy = pkgs.writeShellScript "ac-power-policy" ''
    on_ac=0
    for t in /sys/class/power_supply/*/type; do
      [ "$(${pkgs.coreutils}/bin/cat "$t")" = Mains ] || continue
      read -r online < "''${t%type}online" && [ "$online" = 1 ] && on_ac=1
    done

    if [ "$on_ac" = 1 ]; then
      profile=balanced
      panel=0
    else
      profile=power-saver
      panel=3
    fi

    ${powerprofilesctl} set "$profile" || ${logger} -t ac-power-policy "failed to set profile $profile"
    for p in /sys/class/drm/card*-eDP-*/amdgpu/panel_power_savings; do
      [ -e "$p" ] || continue
      echo "$panel" > "$p" || ${logger} -t ac-power-policy "panel_power_savings=$panel refused"
    done
  '';
in {
  # Re-runs on every AC plug/unplug. A manual `powerprofilesctl set` therefore
  # lasts only until the next plug event.
  services.udev.extraRules = ''
    SUBSYSTEM=="power_supply", ATTR{type}=="Mains", TAG+="systemd", ENV{SYSTEMD_WANTS}+="ac-power-policy.service"
  '';

  systemd.services.ac-power-policy = {
    description = "Apply AC/battery power profile and panel power savings";
    wants = ["power-profiles-daemon.service"];
    after = ["power-profiles-daemon.service"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = policy;
    };
  };
}
