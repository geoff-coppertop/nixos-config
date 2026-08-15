{
  lib,
  pkgs,
  ...
}: let
  # Watches a HOTAS button via evdev (passively — never grabs the device, so
  # DCS and VoiceAttack still see the full stick) and mutes ONLY Discord's
  # PipeWire capture stream while it is held. The real mic source is never
  # touched, so VoiceAttack/VAICOM keep hearing the command. The button binding
  # is runtime state (~/.config/discord-cough-mute/config), captured with
  # `discord-cough-mute --learn`, so changing it needs no rebuild.
  coughMute =
    pkgs.writers.writePython3Bin "discord-cough-mute"
    {
      libraries = [pkgs.python3Packages.evdev];
      flakeIgnore = ["E501"];
    }
    (builtins.readFile ./files/discord-cough-mute.py);
in {
  # The --learn CLI lives on PATH; the service runs the watcher.
  home.packages = [coughMute];

  systemd.user.services.discord-cough-mute = {
    Unit = {
      Description = "Mute Discord's mic while the HOTAS cough button is held";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      ExecStart = "${coughMute}/bin/discord-cough-mute";
      # pactl (PipeWire's pulse client) for per-app stream muting.
      Environment = ["PATH=${lib.makeBinPath [pkgs.pulseaudio]}"];
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = ["graphical-session.target"];
  };
}
