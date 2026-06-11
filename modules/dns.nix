{
  config,
  lib,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkMerge mkOption types;
  cfg = config.custom.dns;
in {
  options.custom.dns = {
    enable = mkEnableOption "DNS stack: unbound recursive resolver + AdGuard Home ad-blocking";

    domain = mkOption {
      type = types.str;
      description = "Local domain resolved to lanIp (e.g. coppertop.ca).";
    };

    lanIp = mkOption {
      type = types.str;
      description = "LAN IP advertised in split-horizon DNS records.";
    };

    lanSubnet = mkOption {
      type = types.str;
      default = "192.168.1.0/24";
      description = "LAN subnet allowed to query unbound directly.";
    };

    subdomains = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Subdomains to resolve to lanIp (e.g. [\"homeassistant\" \"syncthing\"]).";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      # ── unbound: recursive resolver + split-horizon on port 5335 ─────────
      services.unbound = {
        enable = true;
        settings.server = {
          port = 5335;
          interface = ["0.0.0.0"];
          access-control = [
            "127.0.0.0/8 allow"
            "${cfg.lanSubnet} allow"
          ];
          local-zone = ["\"${cfg.domain}.\" static"];
          local-data = map (sub: "\"${sub}.${cfg.domain}. A ${cfg.lanIp}\"") cfg.subdomains;
        };
      };

      # ── AdGuard Home: LAN-facing ad-blocking resolver on port 53 ─────────
      services.adguardhome = {
        enable = true;
        openFirewall = true;
        mutableSettings = true;
        settings.dns = {
          bind_hosts = ["0.0.0.0"];
          port = 53;
          upstream_dns = ["127.0.0.1:5335"];
          bootstrap_dns = ["1.1.1.1" "8.8.8.8"];
        };
      };

      # Expose unbound bypass port and DNS to LAN
      networking.firewall.allowedTCPPorts = [5335];
      networking.firewall.allowedUDPPorts = [53 5335];
    }

    # Self-register Traefik route for AdGuard Home UI
    (mkIf config.custom.traefik.enable {
      services.traefik.dynamicConfigOptions.http = {
        routers.adguard = {
          rule = "Host(`dns.${config.custom.traefik.acme.domain}`)";
          service = "adguard";
          tls = {};
        };
        services.adguard.loadBalancer.servers = [{url = "http://localhost:3000";}];
      };
    })
  ]);
}
