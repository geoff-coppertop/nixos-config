{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkBefore mkEnableOption mkIf mkMerge mkOption optionalAttrs types;
  mkTraefikRoute = import ../lib/traefik-route.nix;
  cfg = config.custom.autoRip;

  tz =
    if config.time.timeZone != null
    then config.time.timeZone
    else "UTC";

  uid = toString cfg.uid;
  gid = toString cfg.gid;
  drive = baseNameOf cfg.opticalDrive;

  deviceOptions = map (d: "--device=${d}:${d}") ([cfg.opticalDrive] ++ cfg.extraDevices);

  yamlFormat = pkgs.formats.yaml {};

  # ARM's loader (arm/config/config.py) reads this file, merges it *over* the
  # full defaults shipped inside the image at ${INSTALLPATH}/setup/arm.yaml,
  # and then rewrites the merged result back here. Two consequences this
  # module relies on:
  #   * Only the keys pinned here need to be present — every other key keeps
  #     ARM's own upstream default, so there is nothing to vendor or re-state.
  #   * INSTALLPATH is the one key the loader dereferences before the merge
  #     (cur_cfg["INSTALLPATH"], no .get), so it must always be written out.
  # `settings` is applied last so a host can override even these.
  # TMDB_API_KEY is a placeholder; see the tmdbApiKeyFile mkIf block below.
  armSettings =
    {
      INSTALLPATH = "/opt/arm/";
      DISABLE_LOGIN = cfg.disableLogin;
      # ARM's own defaults put all three under mediaDir (the NAS mount) --
      # pinning the first two to stateDir keeps raw/transcode I/O off the
      # network; only the finished file below still crosses it.
      RAW_PATH = "/home/arm/raw/";
      TRANSCODE_PATH = "/home/arm/transcode/";
      # A landing zone, not a library folder, and deliberately neither
      # movies/ nor tv/: ARM only has one COMPLETED_PATH, so it can't split
      # output by type itself, and defaulting to one of the two real folders
      # would let tmm scan a still-misclassified item before custom.mediaSort
      # moves it. Neither library folder sees anything until it's sorted.
      COMPLETED_PATH = "/home/arm/media/incoming/";
    }
    // optionalAttrs (cfg.tmdbApiKeyFile != null) {
      METADATA_PROVIDER = "tmdb";
      TMDB_API_KEY = "@TMDB_API_KEY@";
    }
    // cfg.settings;

  armConfigFile = yamlFormat.generate "arm.yaml" armSettings;

  # Host-side trigger: ARM normally starts rips from a udev rule inside a
  # privileged container. Running unprivileged, we instead exec its wrapper on
  # demand. Insert a disc, then run `arm-rip` (optionally `arm-rip sr1`).
  armRip = pkgs.writeShellApplication {
    name = "arm-rip";
    runtimeInputs = [pkgs.podman];
    text = ''
      dev="''${1:-${drive}}"
      exec podman exec --user arm ${cfg.containerName} ${cfg.ripperScript} "$dev"
    '';
  };
in {
  options.custom.autoRip = {
    enable = mkEnableOption "Automatic Ripping Machine (disc rip, transcode, and web UI)";

    image = mkOption {
      type = types.str;
      # Fully qualified — NixOS ships no unqualified-search-registries in
      # /etc/containers/registries.conf, so a bare "user/repo" short name
      # fails podman with "did not resolve to an alias" at container start.
      default = "docker.io/automaticrippingmachine/automatic-ripping-machine:latest";
      description = "ARM container image. Pin to a versioned tag or digest for reproducibility.";
    };

    containerName = mkOption {
      type = types.str;
      default = "arm";
      description = "Name of the podman container.";
    };

    mediaDir = mkOption {
      type = types.str;
      description = "Directory ARM writes finished rips to; point this at the Jellyfin media share.";
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/arm";
      description = "Base directory for ARM's config, logs, database, and CD music output.";
    };

    opticalDrive = mkOption {
      type = types.str;
      default = "/dev/sr0";
      description = "Optical drive block device passed into the container.";
    };

    extraDevices = mkOption {
      type = types.listOf types.str;
      default = [];
      example = ["/dev/sg0"];
      description = "Extra device nodes to pass in. Blu-ray ripping needs the drive's /dev/sg* node.";
    };

    ripperScript = mkOption {
      type = types.str;
      # Confirmed live inside the running container: the image ships
      # docker_arm_wrapper.sh under scripts/docker/, not scripts/arm_wrapper.sh
      # (that name belongs to ARM's non-container/udev install path and isn't
      # present in this image at all).
      default = "/opt/arm/scripts/docker/docker_arm_wrapper.sh";
      description = "In-container path to ARM's rip wrapper, invoked by the `arm-rip` command.";
    };

    webPort = mkOption {
      type = types.port;
      default = 8080;
      description = "Host port that serves the ARM web UI.";
    };

    uid = mkOption {
      type = types.int;
      default = 1000;
      description = "UID ARM runs as; it owns the files ARM writes, so align it with Jellyfin's read access.";
    };

    gid = mkOption {
      type = types.int;
      default = 1000;
      description = "GID ARM runs as.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open webPort broadly in the NixOS firewall. Leave false and set bindAddress/your own firewall rule when a reverse proxy (local or cross-host) fronts it instead.";
    };

    bindAddress = mkOption {
      type = types.str;
      default =
        if cfg.openFirewall
        then "0.0.0.0"
        else "127.0.0.1";
      defaultText = "0.0.0.0 if openFirewall, else 127.0.0.1";
      description = "Address the published web port binds to. Override to \"0.0.0.0\" (or a specific host IP) with openFirewall = false to allow only specific hosts to reach it via your own firewall rule — e.g. a cross-host Traefik proxy.";
    };

    disableLogin = mkOption {
      type = types.bool;
      default = false;
      description = "Turn off ARM's own built-in login screen (its arm.yaml DISABLE_LOGIN key), leaving every page open to anyone who can reach webPort. Only set this true where something else already authenticates every request — e.g. a Traefik forward-auth middleware in front of it — since ARM then trusts whoever reaches it.";
    };

    settings = mkOption {
      inherit (yamlFormat) type;
      default = {};
      example = {
        HB_PRESET_DVD = "HQ 720p30 Surround";
        MINLENGTH = "900";
      };
      description = "Keys written to ARM's arm.yaml, merged over the ones this module pins. ARM fills every key left unset here from the defaults shipped in its image, so list only what should be pinned. This file is rewritten from the Nix store on every activation and reboot: a key set here always wins over the same key changed through ARM's own Settings page, and a key *not* listed here is ARM's to manage until the next rebuild, which resets the file (ARM then re-expands its own defaults for it).";
    };

    extraOptions = mkOption {
      type = types.listOf types.str;
      default = [];
      example = ["--group-add" "cdrom"];
      description = "Extra arguments appended to the podman run command, e.g. --group-add if ARM's user cannot reach the passed device.";
    };

    tmdbApiKeyFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Path to a file holding a TMDb API Key (v3, not the v4 Read Access Token). Without it, ARM can't identify discs.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      virtualisation = {
        podman.enable = true;

        oci-containers = {
          backend = "podman";

          containers.${cfg.containerName} = {
            inherit (cfg) image;
            autoStart = true;

            ports = ["${cfg.bindAddress}:${toString cfg.webPort}:8080"];

            environment = {
              ARM_UID = uid;
              ARM_GID = gid;
              TZ = tz;
            };

            volumes = [
              # /home/arm itself, not just its subdirectories: the image bakes
              # it in at uid:gid 1000:1000, and ARM's own entrypoint only
              # fixes up the subdirectories below, not this directory's own
              # group — confirmed live ("does not have permissions to
              # /home/arm using ${uid}:${gid}... Folder permissions-->
              # ${uid}:1000"). Mounting it host-owned skips that check
              # entirely. See automatic-ripping-machine/automatic-ripping-machine
              # wiki § Docker Troubleshooting.
              "${cfg.stateDir}/home:/home/arm"
              "${cfg.stateDir}/config:/etc/arm/config"
              "${cfg.stateDir}/logs:/home/arm/logs"
              "${cfg.stateDir}/db:/home/arm/db"
              "${cfg.stateDir}/music:/home/arm/Music"
              "${cfg.stateDir}/raw:/home/arm/raw"
              "${cfg.stateDir}/transcode:/home/arm/transcode"
              "${cfg.mediaDir}:/home/arm/media"
            ];

            # No --privileged: pass only the optical drive (plus any extraDevices)
            # and let extraOptions add group access if ARM's user needs it.
            extraOptions = deviceOptions ++ cfg.extraOptions;
          };
        };
      };

      environment.systemPackages = [armRip];

      # ARM's state dirs must exist and be owned by the container UID/GID before
      # the container starts. mediaDir is intentionally left out: it is expected
      # to be a NAS mount whose ownership is governed by the mount, not here.
      systemd.tmpfiles.rules = [
        "d ${cfg.stateDir} 0755 root root -"
        "d ${cfg.stateDir}/home 0775 ${uid} ${gid} -"
        "d ${cfg.stateDir}/config 0775 ${uid} ${gid} -"
        "d ${cfg.stateDir}/logs 0775 ${uid} ${gid} -"
        "d ${cfg.stateDir}/db 0775 ${uid} ${gid} -"
        "d ${cfg.stateDir}/music 0775 ${uid} ${gid} -"
        "d ${cfg.stateDir}/raw 0775 ${uid} ${gid} -"
        "d ${cfg.stateDir}/transcode 0775 ${uid} ${gid} -"
      ];

      # arm.yaml can't be symlinked into the store (the container only sees
      # ${cfg.stateDir}/config, not /nix/store, so a store symlink would
      # dangle inside it — ARM also rewrites this file in place on startup,
      # which needs a real writable file) and tmpfiles' "C"/"C+" line type
      # does not reliably overwrite it either: confirmed live, "C+" only
      # forces a copy into a pre-existing *directory* — for a single regular
      # file destination that already exists it silently no-ops, so a
      # changed arm.yaml never reached disk even after a manual
      # `systemd-tmpfiles --create`. An activation script is what actually
      # forces the overwrite on every switch. `install -D` also creates
      # ${cfg.stateDir}/config itself if missing, ahead of the "d" rule above.
      system.activationScripts.armConfig = {
        deps = ["users" "groups"];
        text = ''
          install -D -m 0664 -o ${uid} -g ${gid} ${armConfigFile} ${cfg.stateDir}/config/arm.yaml
        '';
      };

      # The config is read once at ARM's import time, so a changed arm.yaml
      # only takes effect when the container restarts.
      systemd.services."podman-${cfg.containerName}".restartTriggers = [armConfigFile];

      networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [cfg.webPort];
    }

    # Same secret-injection pattern as modules/ddns.nix.
    (mkIf (cfg.tmdbApiKeyFile != null) {
      systemd.services."podman-${cfg.containerName}".serviceConfig.ExecStartPre = mkBefore [
        (toString (pkgs.writeShellScript "arm-tmdb-api-key" ''
          set -euo pipefail
          key=$(cat "${cfg.tmdbApiKeyFile}")
          sed -i "s|@TMDB_API_KEY@|$key|" ${cfg.stateDir}/config/arm.yaml
        ''))
      ];
    })

    # Self-register a Traefik route when this host itself runs Traefik. The
    # host adds any auth middleware (ARM's own auth is weak). When a
    # different host proxies it cross-host instead, that host defines the
    # route by hand.
    (mkIf config.custom.traefik.enable {
      services.traefik.dynamicConfigOptions.http = mkTraefikRoute {
        name = "arm";
        port = cfg.webPort;
        inherit (config.custom.traefik.acme) domain;
      };
    })
  ]);
}
