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

      environmentFile = mkOption {
        type = types.str;
        description = "Path to env file containing DNS provider credentials (agenix-managed). Format: VAR=value, e.g. CF_DNS_API_TOKEN=xxx.";
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
        inherit (cfg.acme) email dnsProvider environmentFile;
      };
      certs.${domain} = {
        # Cover the apex (for a landing page at the bare domain) and the
        # wildcard: a *.domain wildcard does not match the bare apex, so it
        # needs its own SAN entry.
        domain = domain;
        extraDomainNames = ["*.${domain}"];
        group = "traefik";
        # Without this, Traefik never learns a new cert exists — it keeps
        # serving whatever it loaded at its own startup (the self-signed
        # fallback, if ACME hadn't succeeded yet by then) until manually
        # restarted. Confirmed live: cert issuance succeeded but curl still
        # saw the self-signed chain until traefik.service was restarted.
        reloadServices = ["traefik.service"];
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
