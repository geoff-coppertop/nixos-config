{
  config,
  lib,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkMerge mkOption types;
  mkTraefikRoute = import ../lib/traefik-route.nix;
  cfg = config.custom.zigbee;
in {
  options.custom.zigbee = {
    enable = mkEnableOption "Zigbee2MQTT";

    serialPort = mkOption {
      type = types.str;
      default = "/dev/ttyUSB0";
      description = "Serial port for the Zigbee USB dongle.";
    };

    networkKeyFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Path to agenix-managed file containing the Zigbee network key array. Null on first boot (key is generated).";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      services.zigbee2mqtt = {
        enable = true;
        settings = {
          serial.port = cfg.serialPort;
          mqtt.server = "mqtt://localhost:1883";
          frontend.port = 8082;
          advanced.network_key =
            if cfg.networkKeyFile != null
            then "!secret network_key"
            else "GENERATE";
        };
      };

      users.users.zigbee2mqtt = {
        isSystemUser = true;
        group = "zigbee2mqtt";
        extraGroups = ["dialout"];
      };
      users.groups.zigbee2mqtt = {};
    }

    # Self-register Traefik route
    (mkIf config.custom.traefik.enable {
      services.traefik.dynamicConfigOptions.http = mkTraefikRoute {
        name = "zigbee";
        port = 8082;
        inherit (config.custom.traefik.acme) domain;
      };
    })
  ]);
}
