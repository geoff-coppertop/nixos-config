{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkMerge mkOption types;
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
      default = "/opt/arm/scripts/arm_wrapper.sh";
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

    extraOptions = mkOption {
      type = types.listOf types.str;
      default = [];
      example = ["--group-add" "cdrom"];
      description = "Extra arguments appended to the podman run command, e.g. --group-add if ARM's user cannot reach the passed device.";
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
      ];

      networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [cfg.webPort];
    }

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
