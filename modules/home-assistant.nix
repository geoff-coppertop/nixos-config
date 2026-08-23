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
        Confirmed live: the "Add Integration" search lists every
        integration regardless of this option (that catalog is static
        frontend data), but selecting one whose component isn't listed
        here fails with "Invalid handler specified" — the backend
        component was never installed into the Nix-built package.
      '';
    };

    locationEnvFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Path to an agenix-managed EnvironmentFile providing LOCATION_LAT,
        LOCATION_LON, and LOCATION_ELEVATION — same secret/env-var naming
        as custom.adsb.locationEnvFile (the shared location/coordinates.age
        file), reused rather than duplicated since it's the same home
        address either way. Wires the core homeassistant: latitude/
        longitude/elevation config below via HA's own `!env_var` YAML tag,
        so zone.home (and anything derived from it — met's forecast,
        sun.sun's solar calculations) reflects this repo's own secret
        instead of whatever was typed into onboarding by hand. null skips
        both the EnvironmentFile and the homeassistant: block entirely,
        leaving location exactly as UI-configured (Settings > System >
        General), same as before this option existed.
      '';
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      services.home-assistant = {
        enable = true;
        # No openFirewall here: nixpkgs removed the option (it used to parse
        # the frontend port out of the module's rendered YAML config at eval
        # time, which is no longer possible — see
        # docs/smart-home.md § HTTP config). Defining it at all, true or
        # false, is now an eval-time assertion failure
        # (mkRemovedOptionModule). The desired posture — frontend port 8123
        # closed except to the Sonos UPnP-callback VLAN — is unchanged and
        # keeps working exactly as before, because it was already achieved
        # by NOT opening the port here: hosts/reliant/configuration.nix's
        # networking.firewall.extraCommands carries the one narrow iptables
        # rule, and everything else reaches HA only via Traefik.
        configWritable = true;
        inherit (cfg) extraComponents;
        config =
          {
            # sun: confirmed live — sun.sun doesn't exist at all without this.
            # Unlike ssdp/zeroconf (part of HA's true always-on core bootstrap,
            # set up regardless of YAML), sun is never attempted unless
            # explicitly referenced. Needs zero extra packages (no entry in
            # nixpkgs' component-packages.nix), so no extraComponents change.
            sun = {};
            # mobile_app: confirmed live — extraComponents only bundles the
            # mobile_app Python package into the closure, it does not cause HA
            # to load it at boot. mobile_app also has no "Add Integration" UI
            # flow to trigger setup after the fact (unlike most components):
            # it's driven entirely by the companion app's own registration API
            # call, which is exactly the call that fails with "The mobile_app
            # component is not loaded" when this entry is missing. Same gap as
            # sun above — not part of HA's true always-on core bootstrap
            # (ssdp/zeroconf), so it's never attempted unless explicitly
            # referenced here. `mobile_app` still needs to stay in each host's
            # custom.home-assistant.extraComponents too (that part was correct
            # already, just not sufficient alone without this YAML entry).
            mobile_app = {};
            logger.default = "warning";
            # NOT http.trusted_proxies/use_x_forwarded_for here (previously
            # set): confirmed live, newer HA versions deprecate YAML http:
            # config entirely in favor of UI-managed storage
            # (Settings > System > Network), auto-importing whatever YAML
            # value existed once and then repair-warning "remove the http:
            # block" every boot afterward until it's gone (stops being read
            # at all from HA 2027.2.0). configWritable = true above means the
            # already-imported value persists in an existing instance's own
            # /var/lib/hass/.storage regardless of this file, so removing the
            # YAML is safe for a host that's already run with it set.
            #
            # For a FRESH install (no existing .storage — a from-scratch
            # install on any future host), this is a real gap: Traefik
            # fronts HA on every host with custom.traefik.enable (self-
            # registered below), so HA needs to trust its X-Forwarded-For
            # headers to see real client IPs rather than always 127.0.0.1 —
            # and there is no longer a declarative way to set that. One-time
            # manual step after first boot: Settings > System > Network >
            # enable "Use X-Forwarded-For" and add 127.0.0.1 as a trusted
            # proxy.
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
          };
      };
    }

    # EnvironmentFile is read by systemd itself (root) before the service's
    # own user/sandboxing applies — same reasoning as modules/adsb.nix's
    # identical locationEnvFile wiring, and the same secret file.
    (mkIf (cfg.locationEnvFile != null) {
      systemd.services.home-assistant.serviceConfig.EnvironmentFile = cfg.locationEnvFile;
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
