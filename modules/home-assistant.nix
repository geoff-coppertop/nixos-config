{
  config,
  lib,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkMerge;
  mkTraefikRoute = import ../lib/traefik-route.nix;
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
      services.traefik.dynamicConfigOptions.http = mkTraefikRoute {
        name = "homeassistant";
        subdomain = "home";
        port = 8123;
        inherit (config.custom.traefik.acme) domain;
      };
    })
  ]);
}
