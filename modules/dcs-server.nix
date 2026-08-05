{
  config,
  lib,
  ...
}: let
  inherit (lib) concatStringsSep mkEnableOption mkIf mkMerge mkOption optionals types;
  cfg = config.custom.dcsServer;
  onOff = b:
    if b
    then "1"
    else "0";
in {
  options.custom.dcsServer = {
    enable = mkEnableOption "DCS World dedicated server (Aterfax OCI image under podman)";

    image = mkOption {
      type = types.str;
      default = "docker.io/aterfax/dcs-world-dedicated-server:latest";
      description = "Fully-qualified OCI image reference.";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/dcs-server";
      description = "Host directory bind-mounted to /config (wine prefix, DCS install, Saved Games).";
    };

    autoInstall = mkOption {
      type = types.bool;
      default = true;
      description = "DCSAUTOINSTALL: download and install the DCS server on first container start.";
    };

    autoStart = mkOption {
      type = types.bool;
      default = false;
      description = "AUTOSTART: launch the DCS server when the container starts. Requires saved login credentials and auto-login in the DCS launcher (first-boot GUI step).";
    };

    dcsModules = mkOption {
      type = types.listOf types.str;
      default = [];
      example = ["MARIANAISLANDS_terrain"];
      description = "DCSMODULES: terrain/module identifiers installed by the auto-installer.";
    };

    environmentFiles = mkOption {
      type = types.listOf types.str;
      default = [];
      example = ["/run/agenix/dcs-server-env"];
      description = "Environment files for secrets, e.g. PASSWORD= for the web desktop.";
    };

    gamePort = mkOption {
      type = types.port;
      default = 10308;
      description = "Multiplayer game traffic (TCP+UDP).";
    };

    voiceChat = {
      enable = mkEnableOption "expose the DCS in-game VoIP port";

      port = mkOption {
        type = types.port;
        default = 10309;
        description = "DCS in-game VoIP (TCP+UDP).";
      };
    };

    srs = {
      # Not bundled with the DCS image at all — Aterfax/DCS-World-Dedicated-Server-Docker
      # issue #74 tracks that as an unimplemented feature request. This runs the
      # separate purpose-built jaycadi/dcs-srs-server image as its own container
      # instead of relying on a manual Windows .exe install inside the DCS desktop.
      enable = mkEnableOption "run a DCS-SRS (SimpleRadio) voice server container, separate from the DCS server image";

      image = mkOption {
        type = types.str;
        default = "docker.io/jaycadi/dcs-srs-server:2.3.6.0";
        description = "Fully-qualified OCI image reference for the SRS server.";
      };

      dataDir = mkOption {
        type = types.str;
        default = "/var/lib/dcs-srs-server";
        description = "Host directory bind-mounted for SRS presets.";
      };

      port = mkOption {
        type = types.port;
        default = 5002;
        description = "DCS-SRS voice traffic (TCP+UDP).";
      };

      restApi = {
        enable = mkEnableOption "SRS REST API";

        port = mkOption {
          type = types.port;
          default = 8080;
          description = "SRS REST API port (TCP).";
        };
      };

      environmentFiles = mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["/run/agenix/dcs-srs-env"];
        description = "Env files for secrets, e.g. EXTERNAL_AWACS_MODE_BLUE_PASSWORD=/EXTERNAL_AWACS_MODE_RED_PASSWORD=.";
      };
    };

    desktopPort = mkOption {
      type = types.port;
      default = 3000;
      description = "Webtop web desktop, bound to 127.0.0.1 only — reach via ssh -L.";
    };

    webGuiPort = mkOption {
      type = types.port;
      default = 8088;
      description = "Eagle Dynamics remote-control WebGUI, bound to 127.0.0.1 only — reach via ssh -L.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open the game/VoIP/SRS ports in the host firewall.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      virtualisation.oci-containers = {
        backend = "podman";

        containers.dcs-server = {
          inherit (cfg) image environmentFiles;
          autoStart = true;

          environment = {
            PUID = "1000";
            PGID = "1000";
            TZ = config.time.timeZone;
            DCSAUTOINSTALL = onOff cfg.autoInstall;
            AUTOSTART = onOff cfg.autoStart;
            DCSMODULES = concatStringsSep " " cfg.dcsModules;
          };

          volumes = ["${cfg.dataDir}:/config"];

          ports =
            [
              "${toString cfg.gamePort}:10308/tcp"
              "${toString cfg.gamePort}:10308/udp"
              # Admin surfaces stay loopback-only (webtop has weak default auth);
              # reach via: ssh -L 3000:localhost:3000 -L 8088:localhost:8088 <host>
              "127.0.0.1:${toString cfg.desktopPort}:3000/tcp"
              "127.0.0.1:${toString cfg.webGuiPort}:8088/tcp"
            ]
            ++ optionals cfg.voiceChat.enable [
              "${toString cfg.voiceChat.port}:10309/tcp"
              "${toString cfg.voiceChat.port}:10309/udp"
            ];
        };
      };

      # The linuxserver init chowns /config to PUID:PGID itself.
      systemd.tmpfiles.rules = ["d ${cfg.dataDir} 0755 root root -"];

      networking.firewall = mkIf cfg.openFirewall {
        allowedTCPPorts = [cfg.gamePort] ++ optionals cfg.voiceChat.enable [cfg.voiceChat.port];
        allowedUDPPorts = [cfg.gamePort] ++ optionals cfg.voiceChat.enable [cfg.voiceChat.port];
      };
    }

    (mkIf cfg.srs.enable {
      virtualisation.oci-containers.containers.dcs-srs-server = {
        inherit (cfg.srs) image;
        inherit (cfg.srs) environmentFiles;
        autoStart = true;

        environment = {
          SERVER_PORT = toString cfg.srs.port;
          SERVER_IP = "0.0.0.0";
          HTTP_SERVER_ENABLED =
            if cfg.srs.restApi.enable
            then "true"
            else "false";
          HTTP_SERVER_PORT = toString cfg.srs.restApi.port;
        };

        volumes = ["${cfg.srs.dataDir}/Presets:/docker/dcs-srs/Presets"];

        ports =
          [
            "${toString cfg.srs.port}:${toString cfg.srs.port}/tcp"
            "${toString cfg.srs.port}:${toString cfg.srs.port}/udp"
          ]
          ++ optionals cfg.srs.restApi.enable [
            "${toString cfg.srs.restApi.port}:${toString cfg.srs.restApi.port}/tcp"
          ];
      };

      systemd.tmpfiles.rules = ["d ${cfg.srs.dataDir}/Presets 0755 root root -"];

      networking.firewall = mkIf cfg.openFirewall {
        allowedTCPPorts = [cfg.srs.port] ++ optionals cfg.srs.restApi.enable [cfg.srs.restApi.port];
        allowedUDPPorts = [cfg.srs.port];
      };
    })
  ]);
}
