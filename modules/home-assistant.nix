{
  config,
  lib,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkMerge mkOption optionalAttrs types;
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
        The "Add Integration" search lists every integration regardless of
        this option (static frontend data), but selecting one whose
        component isn't listed here fails with "Invalid handler specified"
        — the backend component was never installed.
      '';
    };

    locationEnvFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Path to an agenix-managed EnvironmentFile providing LOCATION_LAT,
        LOCATION_LON, and LOCATION_ELEVATION — same secret/env-var naming
        as custom.adsb.locationEnvFile (the shared location/coordinates.age
        file, reused since it's the same home address either way). Wires the
        core homeassistant: latitude/longitude/elevation config below via
        HA's own `!env_var` YAML tag, so zone.home (and anything derived
        from it — met's forecast, sun.sun's solar calculations) reflects
        this repo's own secret instead of whatever was typed into onboarding
        by hand. null skips both the EnvironmentFile and the homeassistant:
        block, leaving location exactly as UI-configured.
      '';
    };

    oidc = {
      enable = mkEnableOption ''
        Home Assistant's side of Authelia SSO: renders the auth_oidc:
        configuration.yaml block for the third-party hass-oidc-auth HACS
        component (installed separately via
        services.home-assistant.customComponents), pointed at Authelia's
        OpenID Connect provider (custom.authelia.oidc). Deliberately not
        forward-auth — see docs/smart-home.md § OIDC Login for why.
      '';

      clientId = mkOption {
        type = types.str;
        default = "home-assistant";
        description = ''
          hass-oidc-auth's auth_oidc.client_id. Must match
          custom.authelia.oidc.homeAssistant.clientId on whichever host
          runs Authelia — both default to the same literal for that reason.
        '';
      };

      discoveryUrl = mkOption {
        type = types.str;
        default = "https://${config.custom.authelia.subdomain}.${config.custom.traefik.acme.domain}/.well-known/openid-configuration";
        description = ''
          hass-oidc-auth's auth_oidc.discovery_url — Authelia's OIDC
          discovery endpoint. The default is correct whenever Authelia and
          Home Assistant share the same Traefik/ACME domain, as they do on
          reliant.
        '';
      };

      defaultRedirect = mkOption {
        type = types.bool;
        default = false;
        description = ''
          hass-oidc-auth's auth_oidc.features.default_redirect. When true,
          visiting Home Assistant skips its own login page and redirects
          straight to Authelia — real SSO, not just an extra login button.
          HA's own local login stays reachable as a fallback by appending
          ?skip_oidc_redirect=true to the login URL — worth remembering
          before enabling this, so a broken Authelia never locks out local
          access entirely.
        '';
      };

      clientSecretFile = mkOption {
        type = types.str;
        description = ''
          Path to an agenix-managed file holding the RAW (pre-hash) OIDC
          client secret shared with Authelia — the plaintext value
          hass-oidc-auth's auth_oidc.client_secret needs. Mirror image of
          custom.authelia.oidc.homeAssistant.clientSecretHashFile on the
          Authelia side, which stores only a pbkdf2-sha512 hash of the same
          value: both are generated together via `nix run nixpkgs#authelia
          -- crypto hash generate pbkdf2 --variant sha512 --random`, the raw
          output here and the digest there. Wired as an EnvironmentFile
          (read by systemd as root, same as locationEnvFile above), exposed
          via HA's own `!env_var` YAML tag rather than hass-oidc-auth's
          documented `!secret`/secrets.yaml route, to match this repo's
          existing secret-wiring convention.

          As an EnvironmentFile, its contents must be a
          `HASS_OIDC_CLIENT_SECRET=<value>` line, not the bare value — same
          shape as locationEnvFile's lines above.

          No secret exists at this path yet — secrets-warden needs to
          generate the shared pair above and create a new agenix secret
          for the raw half. See hosts/reliant/README.md § Secrets.
        '';
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      services.home-assistant = {
        enable = true;
        # No openFirewall here: nixpkgs removed the option entirely
        # (mkRemovedOptionModule — see docs/smart-home.md § HTTP config).
        # The desired posture — port 8123 closed except to the Sonos
        # UPnP-callback VLAN — is unchanged, since it was already achieved
        # by NOT opening the port here: hosts/reliant/configuration.nix's
        # firewall.extraCommands carries the one narrow rule, and
        # everything else reaches HA only via Traefik.
        configWritable = true;
        inherit (cfg) extraComponents;
        config =
          {
            # sun, mobile_app, recorder, and history are all set explicitly
            # for the same reason: unlike ssdp/zeroconf (HA's true always-on
            # core bootstrap, set up regardless of YAML), none of these are
            # attempted unless explicitly referenced, so leaving them out is
            # a silent no-op, not a default. Each also needs its own
            # custom.home-assistant.extraComponents entry per host — see
            # docs/smart-home.md § Choosing extraComponents.
            #
            # sun: sun.sun doesn't exist at all without this. No extra
            # package needed (no component-packages.nix entry).
            sun = {};
            # mobile_app: extraComponents only bundles the Python package,
            # it doesn't load it at boot, and mobile_app has no "Add
            # Integration" UI flow to trigger setup afterward — it's driven
            # by the companion app's own registration call, which fails
            # with "The mobile_app component is not loaded" without this.
            mobile_app = {};
            # recorder/history: a history-graph Lovelace card
            # (hosts/reliant/home-assistant/climate-dashboard.nix) reported
            # "History integration is disabled" with neither present.
            # history depends on recorder to have anything to read, so both
            # are needed together.
            recorder = {};
            history = {};
            logger.default = "warning";
            # NOT http.trusted_proxies/use_x_forwarded_for here (previously
            # set): newer HA versions deprecate YAML http: config entirely
            # in favor of UI-managed storage (Settings > System > Network),
            # auto-importing the old YAML value once and then
            # repair-warning to remove the block every boot until it's gone
            # (stops being read at all from HA 2027.2.0). configWritable =
            # true above means the already-imported value persists in
            # /var/lib/hass/.storage regardless of this file, so removing
            # the YAML is safe for a host that's already run with it set.
            #
            # For a FRESH install (no existing .storage), this is a real
            # gap: Traefik fronts HA on every host with custom.traefik.enable
            # (self-registered below), so HA needs to trust its
            # X-Forwarded-For headers to see real client IPs — and there's
            # no longer a declarative way to set that. One-time manual step
            # after first boot: Settings > System > Network > enable "Use
            # X-Forwarded-For" and add 127.0.0.1 as a trusted proxy.
          }
          // optionalAttrs (cfg.locationEnvFile != null) {
            # Confirmed against nixpkgs' home-assistant module source
            # (renderYAMLFile): it sed-unquotes any generated string
            # matching `!word rest`, which is exactly how the module's own
            # docs show wiring `!secret` — `!env_var NAME` is a real HA
            # YAML tag (annotatedyaml's loader, registered on the same
            # loader used for configuration.yaml) that raises if NAME isn't
            # set, so a missing/misconfigured EnvironmentFile fails loudly
            # rather than silently keeping a stale location. Confirmed
            # against HA's own core_config.py: latitude/longitude/elevation
            # here are applied from YAML on every startup (not a one-time
            # onboarding seed like the deprecated http: block above), so
            # this actually keeps zone.home in sync with the secret rather
            # than only seeding it once.
            homeassistant = {
              latitude = "!env_var LOCATION_LAT";
              longitude = "!env_var LOCATION_LON";
              elevation = "!env_var LOCATION_ELEVATION";
            };
          }
          // optionalAttrs cfg.oidc.enable {
            # hass-oidc-auth's own config key, domain "auth_oidc" (matching
            # its manifest.json) — confirmed against its real YAML
            # configuration guide, not guessed
            # (github.com/christiaangoossens/hass-oidc-auth/blob/main/docs/configuration.md).
            # public = false / confidential-client on Authelia's side
            # (modules/authelia.nix's homeAssistantOidcClientFile hardcodes
            # `public: false`) is what makes client_secret required here —
            # a public-client setup would omit it entirely. `!env_var`
            # here is the same mechanism as LOCATION_LAT/LON/ELEVATION
            # above, not hass-oidc-auth's own documented `!secret`/
            # secrets.yaml route — chosen to match this repo's existing
            # convention rather than introducing a second secret-wiring
            # mechanism, and it works because `!word rest` unquoting is a
            # property of the shared annotatedyaml loader, not scoped to
            # any particular integration's config block.
            auth_oidc =
              {
                client_id = cfg.oidc.clientId;
                discovery_url = cfg.oidc.discoveryUrl;
                client_secret = "!env_var HASS_OIDC_CLIENT_SECRET";
              }
              // optionalAttrs cfg.oidc.defaultRedirect {
                features.default_redirect = true;
              };
          };
      };
    }

    # EnvironmentFile is read by systemd itself (root) before the service's
    # own user/sandboxing applies — same reasoning as modules/adsb.nix's
    # identical locationEnvFile wiring, and the same secret file. Each
    # branch contributes a list rather than a bare string so the two can
    # coexist: nixpkgs' systemd freeform "unit option" type concat-merges
    # list-valued definitions of the same key instead of requiring them to
    # be equal, which is only true when every definition is itself a list.
    (mkIf (cfg.locationEnvFile != null) {
      systemd.services.home-assistant.serviceConfig.EnvironmentFile = [cfg.locationEnvFile];
    })

    (mkIf cfg.oidc.enable {
      systemd.services.home-assistant.serviceConfig.EnvironmentFile = [cfg.oidc.clientSecretFile];
    })

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
