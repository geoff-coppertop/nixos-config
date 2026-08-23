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
in {
  options.custom.mediaManager = {
    enable = mkEnableOption "tinyMediaManager library metadata and renaming (web UI)";

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
      description = "Open webPort broadly in the NixOS firewall. Off by default: reach it through a reverse proxy (local or cross-host) instead.";
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

            ports = ["${cfg.bindAddress}:${toString cfg.webPort}:4000"];

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

    # Self-register a Traefik route when this host itself runs Traefik. The
    # host adds any auth middleware (tinyMediaManager's own auth is weak).
    # When a different host proxies it cross-host instead, that host defines
    # the route by hand.
    (mkIf config.custom.traefik.enable {
      services.traefik.dynamicConfigOptions.http = mkTraefikRoute {
        name = "tmm";
        port = cfg.webPort;
        inherit (config.custom.traefik.acme) domain;
      };
    })
  ]);
}
