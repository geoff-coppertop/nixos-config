{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.custom.subtitleAlign;

  # Downloaded subtitles are timed against some other release, never against a
  # re-encoded rip: confirmed live on Casino Royale, where the English file ran
  # a constant 1.2 s late and the French one stepped through +0.5 s, +6 s and
  # +23 s (a different cut). The rip's own embedded English subtitle is timed
  # exactly right, so each downloaded .srt is retimed against it. The offset is
  # allowed to change mid-film (a Viterbi pass over per-cue offsets, each change
  # costing SPLIT mismatched cues), then each stretch is refined to its median
  # residual. A file is only rewritten when that clearly improves how many cues
  # land on a reference event.
  script = pkgs.writeScript "subtitle-align" ("#!${pkgs.python3}/bin/python3\n" + builtins.readFile ./subtitle-align.py);

  setupConfig = pkgs.writeText "subtitle-align.json" (builtins.toJSON {inherit (cfg) mediaDirs;});
in {
  options.custom.subtitleAlign = {
    enable = mkEnableOption "retiming downloaded .srt subtitles against the video's own embedded English subtitle, on a timer";

    mediaDirs = mkOption {
      type = types.listOf types.str;
      description = "Library roots to scan recursively for `<video>.<lang>.srt` files sitting next to a video that carries an embedded English subtitle (e.g. the folders Jellyfin saves downloaded subtitles into).";
    };

    uid = mkOption {
      type = types.int;
      default = 1000;
      description = "UID to run as; needs write access to the subtitle files.";
    };

    gid = mkOption {
      type = types.int;
      default = 1000;
      description = "GID to run as.";
    };

    interval = mkOption {
      type = types.str;
      default = "15min";
      description = "How often to look for new or replaced subtitle files (systemd OnUnitActiveSec value). A file is only processed again if its contents change.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.subtitle-align = {
      description = "Retime downloaded subtitles against the embedded English subtitle";
      path = [pkgs.ffmpeg-headless];
      unitConfig.RequiresMountsFor = cfg.mediaDirs;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${script} ${setupConfig}";
        User = toString cfg.uid;
        Group = toString cfg.gid;
        StateDirectory = "subtitle-align";
        Nice = 10;
        IOSchedulingClass = "idle";
      };
    };

    systemd.timers.subtitle-align = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "10min";
        OnUnitActiveSec = cfg.interval;
      };
    };
  };
}
