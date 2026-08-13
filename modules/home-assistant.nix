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
          # sun: confirmed live — sun.sun doesn't exist at all without this.
          # Unlike ssdp/zeroconf (part of HA's true always-on core bootstrap,
          # set up regardless of YAML), sun is never attempted unless
          # explicitly referenced. Needs zero extra packages (no entry in
          # nixpkgs' component-packages.nix), so no extraComponents change.
          sun = {};
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
