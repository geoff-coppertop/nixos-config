{
  config,
  lib,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkMerge;
  cfg = config.custom.homepage;
  port = 8082;
in {
  options.custom.homepage.enable =
    mkEnableOption "Homepage dashboard served at the domain apex";

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = config.custom.traefik.enable;
          message = "custom.homepage needs custom.traefik on the same host: it is served at the domain apex over TLS.";
        }
      ];
    }

    (mkIf config.custom.traefik.enable (let
      inherit (config.custom.traefik.acme) domain;
    in {
      services.homepage-dashboard = {
        enable = true;
        listenPort = port;
        # Homepage rejects requests whose Host header is not allow-listed;
        # Traefik forwards the apex Host through. Keep the loopback defaults too.
        allowedHosts = "${domain},localhost:${toString port},127.0.0.1:${toString port}";
      };

      services.traefik.dynamicConfigOptions.http = {
        routers.homepage = {
          rule = "Host(`${domain}`)";
          service = "homepage";
          tls = {};
        };
        services.homepage.loadBalancer.servers = [{url = "http://127.0.0.1:${toString port}";}];
      };
    }))
  ]);
}
