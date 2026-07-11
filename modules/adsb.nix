{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkMerge mkOption types;
  mkTraefikRoute = import ../lib/traefik-route.nix;
  cfg = config.custom.adsb;
in {
  options.custom.adsb = {
    enable = mkEnableOption "ADS-B receiver via dump1090";

    device = mkOption {
      type = types.str;
      default = "0";
      description = "RTL-SDR USB device index.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      # plugdev is otherwise only created by modules/debug-probes.nix
      # (custom.debugProbes.enable) — a headless host enabling adsb without
      # that module would fail with EXIT_GROUP (systemd status 216) since
      # the group referenced below wouldn't exist yet. This module needs
      # its own group requirement, not one borrowed from an unrelated module.
      users.groups.plugdev = lib.mkDefault {};

      systemd.services.dump1090 = {
        description = "dump1090 ADS-B receiver";
        wantedBy = ["multi-user.target"];
        after = ["network.target"];
        serviceConfig = {
          # pkgs.dump1090-fa's actual binary is named dump1090 (confirmed
          # live: bin/ contains dump1090, faup1090, view1090 — no
          # dump1090-fa). The wrong name here made the service fail at
          # exec() itself (systemd status 203/EXEC) before any of its own
          # code ever ran.
          ExecStart = "${pkgs.dump1090-fa}/bin/dump1090 --device-index ${cfg.device} --net";
          Restart = "on-failure";
          DynamicUser = true;
          SupplementaryGroups = ["plugdev"];
        };
      };
    }

    # Self-register Traefik route
    (mkIf config.custom.traefik.enable {
      services.traefik.dynamicConfigOptions.http = mkTraefikRoute {
        name = "adsb";
        port = 8080;
        inherit (config.custom.traefik.acme) domain;
      };
    })
  ]);
}
