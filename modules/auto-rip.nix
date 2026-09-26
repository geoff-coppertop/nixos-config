{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkBefore mkEnableOption mkIf mkMerge mkOption optionalAttrs types;
  mkTraefikRoute = import ../lib/traefik-route.nix;
  cfg = config.custom.autoRip;

  handbrakeQsv = pkgs.callPackage ../pkgs/handbrake-qsv.nix {};

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
      # pinning all three to stateDir keeps every ARM write local. The only
      # network transfer left is custom.mediaSort's own push of a finished,
      # already-classified file straight into movies/ or tv/, once, instead
      # of ARM crossing the network first and mediaSort shuffling it a
      # second time on the same share (confirmed live: that second shuffle,
      # implemented as an rsync round-trip rather than a same-device rename,
      # cost 11+ minutes moving 4 titles that were already on the NAS).
      RAW_PATH = "/home/arm/raw/";
      TRANSCODE_PATH = "/home/arm/transcode/";
      # ARM's own default (confirmed against its source, arm/ripper/main.py's
      # delete_raw_files() call): raw MakeMKV output is deleted after a
      # *successful* transcode+move. A failed or aborted job leaves it
      # behind forever -- nothing in ARM cleans that up. scratchMaxAgeDays
      # below is the safety net for that case.
      DELRAWFILES = true;
      # A landing zone, not a library folder, and deliberately neither
      # movies/ nor tv/: ARM only has one COMPLETED_PATH, so it can't split
      # output by type itself, and defaulting to one of the two real folders
      # would let tmm scan a still-misclassified item before custom.mediaSort
      # moves it. Neither library folder sees anything until it's sorted.
      COMPLETED_PATH = "/home/arm/completed/";
    }
    // optionalAttrs (cfg.tmdbApiKeyFile != null) {
      METADATA_PROVIDER = "tmdb";
      TMDB_API_KEY = "@TMDB_API_KEY@";
    }
    // optionalAttrs cfg.hardwareEncode {
      HANDBRAKE_CLI = "${handbrakeQsv}/bin/HandBrakeCLI";
      HANDBRAKE_LOCAL = "${handbrakeQsv}/bin/HandBrakeCLI";
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
      description = "The Jellyfin media share, mounted into the container at /home/arm/media. ARM itself no longer writes here directly -- COMPLETED_PATH is local (see stateDir) -- this is custom.mediaSort's eventual destination and whatever else ARM's own UI browses under /home/arm/media.";
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/arm";
      description = "Base directory for ARM's config, logs, database, and CD music output.";
    };

    scratchMaxAgeDays = mkOption {
      type = types.int;
      default = 3;
      description = "A daily timer deletes anything under stateDir's raw/transcode scratch older than this. A healthy job never lives there this long (DELRAWFILES only cleans up on success), so this is the safety net for a failed or aborted one.";
    };

    hardwareEncode = mkOption {
      type = types.bool;
      default = false;
      description = "Use a QSV-enabled HandBrakeCLI (pkgs/handbrake-qsv.nix) instead of the image's own: passes /dev/dri, the host Nix store, and the render group's GID into the container, and adds pkgs.intel-media-sdk to hardware.graphics.extraPackages (legacy pre-Xe Intel iGPUs; override for a newer GPU needing vpl-gpu-rt). Also needs a HandBrake preset/HB_ARGS naming a qsv_h264/qsv_h265 encoder -- picking a plain x264/x265 preset here still runs in software even with this on.";
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
              "${cfg.stateDir}/completed:/home/arm/completed"
              "${cfg.mediaDir}:/home/arm/media"
            ];

            # No --privileged: pass only the optical drive (plus any extraDevices)
            # and let extraOptions add group access if ARM's user needs it.
            extraOptions = deviceOptions ++ cfg.extraOptions;
          };
        };
      };

      environment.systemPackages = [armRip];

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

      networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [cfg.webPort];

      systemd = {
        # ARM's state dirs must exist and be owned by the container UID/GID
        # before the container starts. mediaDir is intentionally left out:
        # it is expected to be a NAS mount whose ownership is governed by
        # the mount, not here.
        tmpfiles.rules = [
          "d ${cfg.stateDir} 0755 root root -"
          "d ${cfg.stateDir}/home 0775 ${uid} ${gid} -"
          "d ${cfg.stateDir}/config 0775 ${uid} ${gid} -"
          "d ${cfg.stateDir}/logs 0775 ${uid} ${gid} -"
          "d ${cfg.stateDir}/db 0775 ${uid} ${gid} -"
          "d ${cfg.stateDir}/music 0775 ${uid} ${gid} -"
          "d ${cfg.stateDir}/raw 0775 ${uid} ${gid} -"
          "d ${cfg.stateDir}/transcode 0775 ${uid} ${gid} -"
          "d ${cfg.stateDir}/completed 0775 ${uid} ${gid} -"
        ];

        services = {
          # The config is read once at ARM's import time, so a changed
          # arm.yaml only takes effect when the container restarts.
          "podman-${cfg.containerName}".restartTriggers = [armConfigFile];

          arm-scratch-cleanup = {
            description = "Delete ARM's raw/transcode scratch older than scratchMaxAgeDays";
            serviceConfig = {
              Type = "oneshot";
              ExecStart = toString (pkgs.writeShellScript "arm-scratch-cleanup" ''
                set -euo pipefail
                find ${cfg.stateDir}/raw ${cfg.stateDir}/transcode -mindepth 1 -maxdepth 1 \
                  -mtime +${toString cfg.scratchMaxAgeDays} -print -exec rm -rf {} +
              '');
              User = uid;
              Group = gid;
            };
          };
        };

        timers.arm-scratch-cleanup = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = "daily";
            Persistent = true;
          };
        };
      };
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

    (mkIf cfg.hardwareEncode {
      # intel-media-sdk alone isn't a VA-API driver -- it's oneVPL's legacy
      # MFX dispatch library. intel-media-driver (iHD) is the actual driver
      # libva initialises against; confirmed against its own README that it
      # supports Skylake for HEVC encode (shader-based, needs HuC firmware,
      # already covered by this host's existing firmware config).
      hardware.graphics.extraPackages = [pkgs.intel-media-sdk pkgs.intel-media-driver];

      # intel-media-sdk is nixpkgs-marked insecure -- EOL, 5 known local
      # privilege-escalation CVEs (2023-22656/45221/47169/47282/48368).
      # Accepted knowingly: the CVEs are local-privesc inside a podman
      # container with GPU passthrough, a narrower blast radius than a
      # bare-metal install. Confirmed live via CI (nix flake check refusing
      # to evaluate otherwise); version string must track
      # pkgs.intel-media-sdk's actual version or this silently stops
      # matching and CI refuses again.
      nixpkgs.config.permittedInsecurePackages = ["intel-media-sdk-23.2.2"];

      # NixOS doesn't reliably predefine a "render" group (confirmed:
      # tracked upstream as "Specified group 'render' unknown"), but udev's
      # own default rule still assigns /dev/dri/renderD128 to whatever GID
      # the group *named* "render" has -- so declaring it ourselves with a
      # fixed GID keeps both sides (the device's real group, and the
      # container's --group-add below) at the same eval-time-known value.
      users.groups.render.gid = 303;

      virtualisation.oci-containers.containers.${cfg.containerName} = {
        volumes = ["/nix/store:/nix/store:ro"];
        extraOptions = [
          "--device=/dev/dri:/dev/dri"
          "--group-add=${toString config.users.groups.render.gid}"
        ];

        # ARM's container is a foreign (non-NixOS) rootfs -- it has no
        # /run/opengl-driver symlink for libva's default search convention,
        # only whatever this /nix/store bind mount exposes. Point it at
        # intel-media-driver's own output directly instead of relying on
        # any default; confirmed live this was the actual missing piece
        # ("Failed to initialise VAAPI connection" with nothing else set).
        environment = {
          LIBVA_DRIVER_NAME = "iHD";
          LIBVA_DRIVERS_PATH = "${pkgs.intel-media-driver}/lib/dri";
        };
      };
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
