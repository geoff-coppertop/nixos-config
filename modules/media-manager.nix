{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkForce mkIf mkMerge mkOption optionalString types;
  cfg = config.custom.mediaManager;

  # Merges (not overwrites) movieDataSource/tvShowDataSource into whatever tmm
  # already persisted -- these files carry every other setting tmm's own UI
  # writes (scrapers, renamer profiles, ...), and there's no equivalent to
  # ARM's own "merge pinned keys over shipped defaults" loader here to lean
  # on. Skipped (not created) until tmm has run once and written its own
  # defaults -- there is no known-good full default set to seed from Nix.
  mkDataSourceMerge = file: jsonKey: paths:
    optionalString (paths != []) ''
      if [ -f ${cfg.stateDir}/data/${file} ]; then
        tmp=$(mktemp)
        ${pkgs.jq}/bin/jq --argjson ds '${builtins.toJSON paths}' '.${jsonKey} = $ds' \
          ${cfg.stateDir}/data/${file} > "$tmp"
        install -m 0664 -o ${uid} -g ${gid} "$tmp" ${cfg.stateDir}/data/${file}
        rm -f "$tmp"
      fi
    '';

  tz =
    if config.time.timeZone != null
    then config.time.timeZone
    else "UTC";

  uid = toString cfg.uid;
  gid = toString cfg.gid;
in {
  options.custom.mediaManager = {
    enable = mkEnableOption "tinyMediaManager library metadata and renaming (headless CLI, triggered by custom.mediaSort)";

    image = mkOption {
      type = types.str;
      # Fully qualified — see modules/auto-rip.nix's image option for why a
      # bare "user/repo" short name fails podman on this fleet.
      default = "docker.io/tinymediamanager/tinymediamanager:latest";
      description = "tinyMediaManager container image. Pin to a versioned tag or digest.";
    };

    containerName = mkOption {
      type = types.str;
      default = "tinymediamanager";
      description = "Name of the podman container.";
    };

    mediaDir = mkOption {
      type = types.str;
      description = "Library directory to organize; mounted into the container at /media.";
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/tinymediamanager";
      description = "Directory for tinyMediaManager's config and database (container /data).";
    };

    uid = mkOption {
      type = types.int;
      default = 1000;
      description = "UID the container runs as; align with the media library's ownership.";
    };

    gid = mkOption {
      type = types.int;
      default = 1000;
      description = "GID the container runs as.";
    };

    extraOptions = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Extra arguments appended to the podman run command.";
    };

    movieDataSources = mkOption {
      type = types.listOf types.str;
      default = [];
      example = ["/media/movies"];
      description = "Container-side paths (under /media) merged into movies.json's movieDataSource on every activation; other tmm-managed settings in that file are left untouched. Only takes effect once tmm has run at least once and created its own data/ files. Empty leaves Data Sources as whatever tmm's own UI has set.";
    };

    tvShowDataSources = mkOption {
      type = types.listOf types.str;
      default = [];
      example = ["/media/tv"];
      description = "Same as movieDataSources, for tvShows.json's tvShowDataSource.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      virtualisation = {
        podman.enable = true;

        oci-containers = {
          backend = "podman";

          containers.${cfg.containerName} = {
            inherit (cfg) image extraOptions;
            # Not a persistent service: the image's own CMD is tmm's GUI, but
            # overriding it with its CLI flags (confirmed against tmm's own
            # docs -- --updateSources scans data sources, --scrapeUnscraped
            # identifies anything new) runs it headless and lets the process
            # exit on its own once done. autoStart = false since it isn't
            # meant to run continuously; custom.mediaSort's own service
            # starts it (systemd OnSuccess=) right after each sort, via
            # unit name in hosts/*/media.nix, not a shared option.
            autoStart = false;
            cmd = ["--updateSources" "--scrapeUnscraped"];

            environment = {
              TZ = tz;
              USER_ID = uid;
              GROUP_ID = gid;
            };

            volumes = [
              "${cfg.stateDir}:/data"
              "${cfg.mediaDir}:/media"
            ];
          };
        };
      };

      systemd.tmpfiles.rules = [
        "d ${cfg.stateDir} 0775 ${uid} ${gid} -"
      ];

      # oci-containers defaults this service to Restart=always, meant for a
      # long-running server -- here the container is *supposed* to exit once
      # its CLI run finishes, so a restart loop would just fight that.
      systemd.services."podman-${cfg.containerName}".serviceConfig.Restart = mkForce "no";
    }

    (mkIf (cfg.movieDataSources != [] || cfg.tvShowDataSources != []) {
      system.activationScripts.mediaManagerDataSources = {
        deps = ["users" "groups"];
        text =
          mkDataSourceMerge "movies.json" "movieDataSource" cfg.movieDataSources
          + mkDataSourceMerge "tvShows.json" "tvShowDataSource" cfg.tvShowDataSources;
      };
    })
  ]);
}
