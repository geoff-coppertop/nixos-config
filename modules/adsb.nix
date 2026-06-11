{
  config,
  lib,
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
      services.dump1090 = {
        enable = true;
        inherit (cfg) device;
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
