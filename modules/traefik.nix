{
  config,
  lib,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.custom.traefik;
  inherit (cfg.acme) domain;
in {
  options.custom.traefik = {
    enable = mkEnableOption "Traefik reverse proxy with ACME DNS-01";

    acme = {
      email = mkOption {
        type = types.str;
        description = "ACME account email address.";
      };

      dnsProvider = mkOption {
        type = types.str;
        default = "cloudflare";
        description = "lego DNS provider name.";
      };

      credentialsFile = mkOption {
        type = types.str;
        description = "Path to the DNS provider credentials file (agenix-managed).";
      };

      domain = mkOption {
        type = types.str;
        description = "Base domain. A wildcard cert for *.domain is requested.";
      };
    };
  };

  config = mkIf cfg.enable {
    security.acme = {
      acceptTerms = true;
      defaults = {
        inherit (cfg.acme) email dnsProvider credentialsFile;
      };
      certs.${domain} = {
        domain = "*.${domain}";
        group = "traefik";
      };
    };

    services.traefik = {
      enable = true;

      staticConfigOptions = {
        entryPoints = {
          web = {
            address = ":80";
            http.redirections.entryPoint = {
              to = "websecure";
              scheme = "https";
            };
          };
          websecure.address = ":443";
        };
      };

      dynamicConfigOptions.tls.stores.default.defaultCertificate = {
        certFile = "/var/lib/acme/${domain}/fullchain.pem";
        keyFile = "/var/lib/acme/${domain}/key.pem";
      };
    };

    users.users.traefik.extraGroups = ["acme"];

    networking.firewall.allowedTCPPorts = [80 443];
  };
}
