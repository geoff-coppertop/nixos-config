{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkOption optionalString types;
  cfg = config.custom.mediaSort;

  uid = toString cfg.uid;
  gid = toString cfg.gid;

  # Sorts ARM's finished rips out of its local completed/ into the NAS's
  # movies/ or tv/, using ARM's own movie/series identification from its job
  # database (VIDEOTYPE=auto against its metadata provider) instead of
  # re-guessing from a filename. This is the one place a finished rip
  # actually crosses onto the network -- completedDir is local disk
  # (custom.autoRip's stateDir/completed), so unlike an earlier design where
  # ARM itself wrote across the network and this script then reshuffled the
  # file a second time on the same NAS share, there is now exactly one
  # network transfer per file. Idempotent by construction: a job already
  # sorted has no directory left under completedDir, so it's silently
  # skipped next run -- no separate state file.
  mediaSort = pkgs.writeShellApplication {
    name = "media-sort";
    runtimeInputs = [pkgs.sqlite pkgs.jq pkgs.rsync];
    text =
      ''
        sqlite3 -json ${cfg.dbFile} \
          "SELECT path, video_type FROM job WHERE status = 'success' AND video_type IN ('movie', 'series')" |
          jq -c '.[]' |
          while read -r row; do
            path=$(jq -r '.path' <<<"$row")
            video_type=$(jq -r '.video_type' <<<"$row")

            # ARM nests output under its own subfolders (completedDir/movies/,
            # completedDir/unidentified/, ...) rather than completedDir
            # directly -- confirmed live. video_type from the database is
            # authoritative regardless of which of ARM's own bucket names it
            # landed under, so search for it instead of assuming a fixed
            # relative path.
            src=$(find "${cfg.completedDir}" -mindepth 1 -maxdepth 3 -type d -name "$(basename "$path")" -print -quit)
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
      ''
      # A second, DB-less leg for custom.mediaRipping's import-disc: it has no
      # metadata source to classify by (no TMDB lookup, no arm.db row), so the
      # operator already bucketed the files under importDir/movies/ or
      # importDir/tv/<show>/Season N/ at import time -- the folder they chose
      # to put it under *is* the classification, so this just merges those
      # trees straight into the library, no per-item lookup needed.
      + optionalString (cfg.importDir != null) ''
        for bucket in movies tv; do
          if [ -d "${cfg.importDir}/$bucket" ]; then
            rsync -a --ignore-existing --remove-source-files "${cfg.importDir}/$bucket"/ "${cfg.mediaDir}/$bucket"/
            find "${cfg.importDir}/$bucket" -depth -type d -empty -delete
          fi
        done
      '';
  };
in {
  options.custom.mediaSort = {
    enable = mkEnableOption "sort ARM's (and optionally custom.mediaRipping's import-disc) finished rips into movies/tv/, on a timer";

    dbFile = mkOption {
      type = types.str;
      description = "Path to ARM's own arm.db (job.status/job.video_type/job.path), e.g. \${custom.autoRip.stateDir}/db/arm.db.";
    };

    completedDir = mkOption {
      type = types.str;
      description = "Local path to ARM's own completed/ (COMPLETED_PATH), awaiting sort -- e.g. \${custom.autoRip.stateDir}/completed. Already created by custom.autoRip's own tmpfiles.rules.";
    };

    mediaDir = mkOption {
      type = types.str;
      description = "Media share root holding movies/ and tv/ -- same value as custom.autoRip.mediaDir and custom.mediaManager.mediaDir.";
    };

    uid = mkOption {
      type = types.int;
      default = 1000;
      description = "UID to run as; needs read access to dbFile and completedDir, and write access to mediaDir.";
    };

    gid = mkOption {
      type = types.int;
      default = 1000;
      description = "GID to run as.";
    };

    interval = mkOption {
      type = types.str;
      default = "15min";
      description = "How often to check completedDir for newly finished rips (systemd OnUnitActiveSec value).";
    };

    importDir = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "custom.mediaRipping's import-disc staging root (its movies/ and tv/<show>/Season N/ subtrees are merged straight into mediaDir, no classification lookup needed -- the operator already bucketed them at import time). null disables this leg entirely.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.media-sort = {
      description = "Sort ARM's completed/ rips into movies/tv/";
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
