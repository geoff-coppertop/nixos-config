{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.custom.mediaSort;

  uid = toString cfg.uid;
  gid = toString cfg.gid;

  # Sorts ARM's finished rips out of incoming/ into movies/ or tv/, using
  # ARM's own movie/series identification from its job database (VIDEOTYPE=
  # auto against its metadata provider) instead of re-guessing from a
  # filename. Idempotent by construction: a job already sorted has no
  # directory left under incoming/, so it's silently skipped next run -- no
  # separate state file.
  mediaSort = pkgs.writeShellApplication {
    name = "media-sort";
    runtimeInputs = [pkgs.sqlite pkgs.jq pkgs.rsync];
    text = ''
      sqlite3 -json ${cfg.dbFile} \
        "SELECT path, video_type FROM job WHERE status = 'success' AND video_type IN ('movie', 'series')" |
        jq -c '.[]' |
        while read -r row; do
          path=$(jq -r '.path' <<<"$row")
          video_type=$(jq -r '.video_type' <<<"$row")

          # ARM nests output under its own subfolders (incoming/movies/,
          # incoming/unidentified/, ...) rather than incoming/ directly --
          # confirmed live. video_type from the database is authoritative
          # regardless of which of ARM's own bucket names it landed under,
          # so search for it instead of assuming a fixed relative path.
          src=$(find "${cfg.mediaDir}/incoming" -mindepth 1 -maxdepth 3 -type d -name "$(basename "$path")" -print -quit)
          [ -n "$src" ] || continue # already sorted, or nothing landed under this name

          case "$video_type" in
            movie) dest_dir="${cfg.mediaDir}/movies" ;;
            series) dest_dir="${cfg.mediaDir}/tv" ;;
            *) continue ;;
          esac

          dest="$dest_dir/$(basename "$src")"
          echo "Sorting $(basename "$src") -> $dest_dir/"
          mkdir -p "$dest"
          # --ignore-existing: never overwrite something tmm already renamed
          # at the destination. -a merges into an existing same-named show
          # folder instead of nesting (unlike mv, which would move src
          # *inside* an existing dest).
          rsync -a --ignore-existing --remove-source-files "$src"/ "$dest"/
          find "$src" -depth -type d -empty -delete
        done
    '';
  };
in {
  options.custom.mediaSort = {
    enable = mkEnableOption "sort ARM's finished rips out of incoming/ into movies/tv/, on a timer";

    dbFile = mkOption {
      type = types.str;
      description = "Path to ARM's own arm.db (job.status/job.video_type/job.path), e.g. \${custom.autoRip.stateDir}/db/arm.db.";
    };

    mediaDir = mkOption {
      type = types.str;
      description = "Media share root holding incoming/, movies/, and tv/ -- same value as custom.autoRip.mediaDir and custom.mediaManager.mediaDir.";
    };

    uid = mkOption {
      type = types.int;
      default = 1000;
      description = "UID to run as; needs read access to dbFile and write access to mediaDir.";
    };

    gid = mkOption {
      type = types.int;
      default = 1000;
      description = "GID to run as.";
    };

    interval = mkOption {
      type = types.str;
      default = "15min";
      description = "How often to check incoming/ for newly finished rips (systemd OnUnitActiveSec value).";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.media-sort = {
      description = "Sort ARM's incoming/ rips into movies/tv/";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${mediaSort}/bin/media-sort";
        User = uid;
        Group = gid;
      };
    };

    systemd.timers.media-sort = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = cfg.interval;
      };
    };
  };
}
