{
  config,
  lib,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkMerge mkOption types;
  mkTraefikRoute = import ../lib/traefik-route.nix;
  cfg = config.custom.mediaManager;

  tz =
    if config.time.timeZone != null
    then config.time.timeZone
    else "UTC";

  uid = toString cfg.uid;
  gid = toString cfg.gid;

  # Bind the published web port to loopback when the firewall is closed: podman
  # port publishing bypasses the NixOS firewall, so openFirewall = false alone
  # would not actually close the port.
  bindAddr =
    if cfg.openFirewall
    then "0.0.0.0"
    else "127.0.0.1";
in {
  options.custom.mediaManager = {
    enable = mkEnableOption "tinyMediaManager library metadata and renaming (web UI)";

    image = mkOption {
      type = types.str;
      default = "tinymediamanager/tinymediamanager:latest";
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

    webPort = mkOption {
      type = types.port;
      default = 4000;
      description = "Host port for the tinyMediaManager web UI.";
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

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open webPort in the firewall. Off by default: reach it through Traefik.";
    };

    extraOptions = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Extra arguments appended to the podman run command.";
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
            autoStart = true;

            ports = ["${bindAddr}:${toString cfg.webPort}:4000"];

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

      networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [cfg.webPort];
    }

    # Self-register a Traefik route when this host runs Traefik. The host adds
    # any auth middleware (tinyMediaManager's own auth is weak).
    (mkIf config.custom.traefik.enable {
      services.traefik.dynamicConfigOptions.http = mkTraefikRoute {
        name = "tmm";
        port = cfg.webPort;
        inherit (config.custom.traefik.acme) domain;
      };
    })
  ]);
}
