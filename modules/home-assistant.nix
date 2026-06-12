{
  config,
  lib,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkMerge;
  cfg = config.custom.home-assistant;
in {
  options.custom.home-assistant = {
    enable = mkEnableOption "Home Assistant";
  };

  config = mkIf cfg.enable (mkMerge [
    {
      services.home-assistant = {
        enable = true;
        openFirewall = false;
        configWritable = true;
        config = {
          http = {
            trusted_proxies = ["127.0.0.1"];
            use_x_forwarded_for = true;
          };
          logger.default = "warning";
        };
      };
    }

    # Self-register Traefik route
    (mkIf config.custom.traefik.enable {
      services.traefik.dynamicConfigOptions.http = {
        routers.homeassistant = {
          rule = "Host(`homeassistant.${config.custom.traefik.acme.domain}`)";
          service = "homeassistant";
          tls = {};
        };
        services.homeassistant.loadBalancer.servers = [{url = "http://localhost:8123";}];
      };
    })
  ]);
}
