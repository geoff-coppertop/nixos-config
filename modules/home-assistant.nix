{
  config,
  lib,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkMerge mkOption types;
  mkTraefikRoute = import ../lib/traefik-route.nix;
  cfg = config.custom.home-assistant;
in {
  options.custom.home-assistant = {
    enable = mkEnableOption "Home Assistant";

    extraComponents = mkOption {
      type = types.listOf types.str;
      default = [];
      description = ''
        Integration components to bundle into the Home Assistant Python
        environment, beyond the small built-in default_config baseline.
        Confirmed live: the "Add Integration" search lists every
        integration regardless of this option (that catalog is static
        frontend data), but selecting one whose component isn't listed
        here fails with "Invalid handler specified" — the backend
        component was never installed into the Nix-built package.
      '';
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      services.home-assistant = {
        enable = true;
        openFirewall = false;
        configWritable = true;
        inherit (cfg) extraComponents;
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
