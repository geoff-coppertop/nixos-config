{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkMerge mkOption types;
  cfg = config.custom.adsb;
in {
  options.custom.adsb = {
    enable = mkEnableOption "ADS-B receiver via dump1090";

    device = mkOption {
      type = types.str;
      default = "0";
      description = "RTL-SDR USB device index.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      systemd.services.dump1090 = {
        description = "dump1090 ADS-B receiver";
        wantedBy = ["multi-user.target"];
        after = ["network.target"];
        serviceConfig = {
          ExecStart = "${pkgs.dump1090-fa}/bin/dump1090-fa --device-index ${cfg.device} --net";
          Restart = "on-failure";
          DynamicUser = true;
          SupplementaryGroups = ["plugdev"];
        };
      };
    }

    # Self-register Traefik route
    (mkIf config.custom.traefik.enable {
      services.traefik.dynamicConfigOptions.http = {
        routers.adsb = {
          rule = "Host(`adsb.${config.custom.traefik.acme.domain}`)";
          service = "adsb";
          tls = {};
        };
        services.adsb.loadBalancer.servers = [{url = "http://localhost:8080";}];
      };
    })
  ]);
}
