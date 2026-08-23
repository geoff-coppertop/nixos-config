{
  config,
  lib,
  ...
}: let
  inherit (lib) mapAttrsToList mkEnableOption mkIf mkMerge mkOption optional types;
  mkTraefikRoute = import ../lib/traefik-route.nix;
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
      description = "Subdomains to resolve to lanIp (e.g. [\"homeassistant\" \"zigbee\"]).";
    };

    apexRecord = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "IP the bare domain (apex) resolves to locally, e.g. for a landing page. Null lets the apex recurse to public DNS (kept for ACME SOA discovery on the DNS host — only an A record is overridden, so SOA/NS/TXT still recurse).";
    };

    extraRecords = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = "Extra A records (hostname -> IP) served for the local domain, for names whose Traefik ingress lives on another host (e.g. {jellyfin = \"192.168.20.15\";}).";
    };

    adminSubdomain = mkOption {
      type = types.str;
      default = "dns";
      description = "Subdomain for AdGuard Home's admin UI when custom.traefik.enable is set on this host.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      # ── unbound: recursive resolver + split-horizon on port 5335 ─────────
      services.unbound = {
        enable = true;
        enableRootTrustAnchor = true;

        settings.server = {
          port = 5335;
          interface = ["0.0.0.0"];

          # DNS Flag Day 2020 recommendation: keep UDP responses under the
          # unfragmented-delivery ceiling. Standard practice from the
          # reference Pi-hole+unbound config.
          edns-buffer-size = 1232;
          harden-glue = true;
          prefetch = true;
          access-control = [
            "127.0.0.0/8 allow"
            "${cfg.lanSubnet} allow"
          ];
          # transparent, not static: static answers only exactly what's in
          # local-data and NXDOMAINs everything else in the zone — including
          # SOA/NS queries. Confirmed live: that broke ACME DNS-01 issuance,
          # since lego runs ON this host and finds the Cloudflare zone via a
          # real SOA walk from _acme-challenge.<domain>. up the tree; with
          # "static" our own resolver told it coppertop.ca doesn't exist at
          # all, so it walked past it to the public suffix "ca." and failed.
          # transparent still answers the subdomains below from local-data,
          # but falls through to real recursion for everything else in the
          # zone (SOA, NS, the bare domain, any other public record).
          local-zone = ["\"${cfg.domain}.\" transparent"];
          local-data =
            map (sub: "\"${sub}.${cfg.domain}. A ${cfg.lanIp}\"") cfg.subdomains
            ++ optional (cfg.apexRecord != null) "\"${cfg.domain}. A ${cfg.apexRecord}\""
            ++ mapAttrsToList (host: ip: "\"${host}.${cfg.domain}. A ${ip}\"") cfg.extraRecords;
        };
      };

      # ── AdGuard Home: LAN-facing ad-blocking resolver on port 53 ─────────
      services.adguardhome = {
        enable = true;
        # openFirewall only opens the admin web UI (default port 3000, not
        # the DNS resolver — that's the explicit allowedTCPPorts/UDPPorts
        # below) with no source restriction at all. No host needs that open:
        # reliant reaches its own admin UI via Traefik on 127.0.0.1
        # regardless of the firewall, and excelsior's cross-host case (see
        # docs/homelab-network.md § Second DNS Instance) opens it explicitly,
        # restricted to reliant's IP, in hosts/excelsior/configuration.nix.
        openFirewall = false;
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

      # The Pi has no RTC/battery-backed clock, so on every boot the kernel
      # clock starts wrong (often way in the past) until systemd-timesyncd
      # completes its first NTP sync. Confirmed live: booting with DNSSEC
      # validation on, unbound started serving before that first sync landed
      # and every lookup died with "DNSKEY rrset is not secure" — real
      # signatures failing validation against a clock that hadn't caught up
      # yet, not an upstream problem. NTP itself isn't blocked by this: the
      # box resolves via DHCP-provided nameservers (the router) at boot, not
      # through unbound, so there's no circular DNS dependency here.
      #
      # systemd-time-wait-sync blocks on the kernel's "clock synchronized"
      # flag, which timesyncd sets after its first successful sync; it isn't
      # pulled in by anything by default, so wantedBy enables it. Ordering
      # unbound after time-sync.target means it never starts validating
      # until that flag is actually set, letting DNSSEC stay on permanently
      # instead of needing to be disabled for this host.
      systemd.services.systemd-time-wait-sync.wantedBy = ["sysinit.target"];
      systemd.services.unbound = {
        after = ["time-sync.target"];
        wants = ["time-sync.target"];
      };
    }

    # Self-register Traefik route for AdGuard Home UI
    (mkIf config.custom.traefik.enable {
      services.traefik.dynamicConfigOptions.http = mkTraefikRoute {
        name = "adguard";
        subdomain = cfg.adminSubdomain;
        # Follows services.adguardhome.port (upstream default 3000) rather
        # than a literal 3000: reliant's custom.bambuddy asserts against that
        # same default to flag its own virtual-printer port collision (see
        # modules/bambuddy.nix and hosts/reliant/README.md § Bambuddy), and
        # the fix that assertion points at is moving
        # services.adguardhome.port. A hardcoded 3000 here would silently
        # decouple this route from that port the moment someone made that
        # move, breaking the admin UI with no error until someone noticed.
        port = config.services.adguardhome.port;
        inherit (config.custom.traefik.acme) domain;
      };
    })
  ]);
}
