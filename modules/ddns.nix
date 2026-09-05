{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.custom.ddns;
in {
  options.custom.ddns = {
    enable = mkEnableOption "ddclient: keep Cloudflare DNS records pointed at this network's current public IP";

    domain = mkOption {
      type = types.str;
      description = ''
        Cloudflare zone apex to keep updated (a single A record). Every
        subdomain follows automatically through this zone's existing
        `*.<domain> CNAME <domain>` wildcard record -- not managed by this
        module, since a CNAME target needs no separate update of its own.
        That wildcard record must already exist in Cloudflare (as a CNAME
        to the apex, not as its own A record) for subdomains to resolve
        publicly at all.
      '';
    };

    apiTokenFile = mkOption {
      type = types.str;
      description = ''
        Path to the agenix-managed env file already used by
        `custom.traefik.acme.environmentFile` for the same Cloudflare zone
        (format `CLOUDFLARE_DNS_API_TOKEN=<token>` -- lego's actual env var
        for the cloudflare provider, confirmed against the real secret on
        reliant), e.g. `/run/agenix/traefik/cloudflare-api-token`. Reused
        as-is rather than duplicated: ddclient needs the bare token, not an
        env-var line, so this module strips the
        `CLOUDFLARE_DNS_API_TOKEN=` prefix itself at service start.
      '';
    };

    interval = mkOption {
      type = types.str;
      default = "10min";
      description = "How often ddclient checks the public IP and updates Cloudflare if it changed.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.custom.traefik.enable;
        message = "custom.ddns reuses custom.traefik's Cloudflare API token file and runs as its 'traefik' system user to read it without a permission workaround -- enable custom.traefik first.";
      }
    ];

    services.ddclient = {
      enable = true;
      protocol = "cloudflare";
      zone = cfg.domain;
      # Only the apex needs a direct update -- this zone's *.<domain>
      # wildcard is a CNAME to the apex (confirmed live in the Cloudflare
      # dashboard), not its own A record, so it follows automatically.
      # Listing it here too would make ddclient look for an A record named
      # "*.<domain>" that doesn't exist and fail that entry every run (same
      # class of failure as the usev6 note below).
      domains = [cfg.domain];
      # Literal "token", not a placeholder for the credential itself --
      # ddclient's cloudflare protocol keys off this exact string to send
      # `Authorization: Bearer <password>` instead of the legacy
      # X-Auth-Email/X-Auth-Key Global-API-Key headers (confirmed against
      # ddclient's own source, nic_cloudflare_update in ddclient.in).
      username = "token";
      # Populated by the ExecStartPre below, inside this service's own
      # RuntimeDirectory (/run/ddclient -- fixed by the ddclient module
      # itself, not configurable, see nixpkgs' services.ddclient module).
      passwordFile = "/run/ddclient/token";
      # This zone's public-facing record is tracked for IPv4 only. Leaving
      # the module's default usev6 enabled would make every run also probe
      # for an AAAA record that was never created for the apex --
      # ddclient's cloudflare protocol only PATCHes a record that already
      # exists, it never creates one -- logging a spurious failure every
      # interval for a record this setup was never asked to manage.
      usev6 = "";
      inherit (cfg) interval;
    };

    # ddclient's own passwordFile mechanism (nixpkgs' services.ddclient
    # module) substitutes a secret file's whole content verbatim as the
    # password value. custom.traefik.acme.environmentFile's only copy of
    # this token is formatted as an EnvironmentFile= line
    # (CLOUDFLARE_DNS_API_TOKEN=<token>), for acme's own environmentFile consumer --
    # not the bare token ddclient wants. Rather than asking secrets-warden
    # for a second, differently-formatted copy of the same credential, this
    # runs ddclient as the existing "traefik" system user (already the owner
    # of that file, mode 0400) and strips the prefix into a private runtime
    # file at service start.
    #
    # DynamicUser is turned off (rather than left on and granted the
    # "traefik" group) because the token file it would need to read still
    # has to land somewhere ddclient's own dynamic, per-invocation UID can
    # read, and that UID isn't known ahead of time to hand it exclusive
    # ownership -- fixing the service to the real "traefik" user avoids that
    # entirely: the ExecStartPre below runs as "traefik" too, so the
    # extracted token file it writes into this service's own RuntimeDirectory
    # never needs to be more than owner-readable.
    systemd.services.ddclient.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "traefik";
      Group = "traefik";
      ExecStartPre = lib.mkBefore [
        (toString (pkgs.writeShellScript "ddclient-cloudflare-token" ''
          set -euo pipefail
          token=$(sed -n 's/^CLOUDFLARE_DNS_API_TOKEN=//p' "${cfg.apiTokenFile}")
          if [ -z "$token" ]; then
            echo "custom.ddns: no CLOUDFLARE_DNS_API_TOKEN= line found in ${cfg.apiTokenFile}" >&2
            exit 1
          fi
          install -m 600 /dev/null /run/ddclient/token
          printf '%s' "$token" > /run/ddclient/token
        ''))
      ];
    };
  };
}
