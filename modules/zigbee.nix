{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkMerge mkOption types;
  mkTraefikRoute = import ../lib/traefik-route.nix;
  cfg = config.custom.zigbee;
in {
  options.custom.zigbee = {
    enable = mkEnableOption "Zigbee2MQTT";

    serialPort = mkOption {
      type = types.str;
      default = "/dev/ttyUSB0";
      description = "Serial port for the Zigbee USB dongle.";
    };

    networkKeyFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Path to an agenix-managed file whose content is the Zigbee network key as a bracketed byte array (e.g. \"[1,2,...,16]\"), extracted from the coordinator after it first commissions. Null on first boot (key is generated).";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      services.zigbee2mqtt = {
        enable = true;
        settings = {
          serial.port = cfg.serialPort;
          mqtt.server = "mqtt://localhost:1883";
          frontend.port = 8082;
          advanced.network_key =
            if cfg.networkKeyFile != null
            then "@NETWORK_KEY@"
            else "GENERATE";
        };
      };

      # services.zigbee2mqtt.settings is serialized to YAML at Nix build
      # time — there's no secrets-file mechanism in the upstream module (the
      # "!secret" YAML tag zigbee2mqtt itself supports has nothing wiring a
      # companion secrets.yaml here). Confirmed live: the ExecStartPre that
      # copies the rendered configuration.yaml into place runs on every
      # restart, so with no networkKeyFile it kept setting network_key to
      # the literal string "GENERATE" over and over — zigbee-herdsman
      # regenerated a fresh random key each time, mismatched what the
      # coordinator already had committed, and crash-looped forever.
      # Substituting the real key in at activation time, the same pattern
      # roles/common/wifi.nix uses for secrets that can't reach a Nix
      # build-time setting.
      #
      # This must be a serviceConfig.ExecStartPre entry, not preStart:
      # confirmed live that NixOS's systemd module always prepends the
      # preStart-generated script BEFORE the upstream module's own
      # ExecStartPre (the cp of configuration.yaml into place) — so a
      # preStart sed ran first and was immediately clobbered by the cp
      # running second, leaving the literal "@NETWORK_KEY@" placeholder in
      # place. mkAfter here sorts this entry after the upstream cp's
      # default-priority ExecStartPre so the substitution actually sticks.
      #
      # The sed pattern matches the quotes too, not just the placeholder:
      # Nix's YAML generator quotes plain strings, so the rendered file has
      # network_key: '@NETWORK_KEY@' (single quotes — confirmed live via
      # the rendered store path, e.g.
      # /nix/store/*-zigbee2mqtt.yaml:2:  network_key: '@NETWORK_KEY@').
      # Replacing only the placeholder token left the quotes in place, so
      # zigbee2mqtt parsed the result as a quoted string ('[1,2,...]') and
      # rejected it — advanced.network_key must be an unquoted YAML flow
      # sequence to parse as an array.
      systemd.services.zigbee2mqtt.serviceConfig.ExecStartPre =
        lib.mkIf (cfg.networkKeyFile != null)
        (lib.mkAfter [
          "${pkgs.writeShellScript "zigbee2mqtt-inject-network-key" ''
            ${pkgs.gnused}/bin/sed -i \
              "s|'@NETWORK_KEY@'|$(cat ${cfg.networkKeyFile})|" \
              /var/lib/zigbee2mqtt/configuration.yaml
          ''}"
        ]);

      users.users.zigbee2mqtt = {
        isSystemUser = true;
        group = "zigbee2mqtt";
        extraGroups = ["dialout"];
      };
      users.groups.zigbee2mqtt = {};
    }

    # Self-register Traefik route
    (mkIf config.custom.traefik.enable {
      services.traefik.dynamicConfigOptions.http = mkTraefikRoute {
        name = "zigbee";
        port = 8082;
        inherit (config.custom.traefik.acme) domain;
      };
    })
  ]);
}
