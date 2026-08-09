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

    locationEnvFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Path to an agenix-managed EnvironmentFile providing LOCATION_LAT
        and LOCATION_LON (receiver coordinates, for the map center/range
        rings and surface-position decoding). Kept out of the Nix
        store/git history as a secret rather than a plain option value
        since it resolves to a home address; null skips passing
        --lat/--lon entirely. Same secret/env-var naming as the shared
        location/coordinates.age file, since a future weather station
        module is expected to need the same coordinates.
      '';
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      # plugdev is otherwise only created by modules/debug-probes.nix
      # (custom.debugProbes.enable) — a headless host enabling adsb without
      # that module would fail with EXIT_GROUP (systemd status 216) since
      # the group referenced below wouldn't exist yet. This module needs
      # its own group requirement, not one borrowed from an unrelated module.
      #
      # A fixed system user, not DynamicUser: confirmed live that
      # /var/lib/dump1090 under DynamicUser is a symlink into
      # /var/lib/private/dump1090, and /var/lib/private itself is
      # root-only — chmod on the visible symlink target doesn't reach far
      # enough, nginx (an unrelated user) is blocked from ever traversing
      # in regardless of StateDirectoryMode. A real user + a normal
      # (non-private) StateDirectory sidesteps that indirection entirely.
      users = {
        groups = {
          plugdev = lib.mkDefault {};
          dump1090 = {};
        };
        users.dump1090 = {
          isSystemUser = true;
          group = "dump1090";
          extraGroups = ["plugdev"];
        };
      };

      # Confirmed live: with the dongle physically plugged in, dump1090
      # found it ("device #0") but failed with "Permission denied" — the
      # dump1090 user's extraGroups=["plugdev"] above only helps if the
      # RTL-SDR USB device node is actually udev-tagged into that group,
      # which nothing did. hardware.rtl-sdr installs the udev rules that
      # do that (RTL-SDR VID/PIDs → group plugdev, mode 0666) and
      # blacklists the kernel's DVB-T driver, which otherwise claims the
      # same USB device before dump1090 can open it.
      hardware.rtl-sdr.enable = true;

      systemd.services.dump1090 = {
        description = "dump1090 ADS-B receiver";
        wantedBy = ["multi-user.target"];
        after = ["network.target"];
        serviceConfig =
          lib.optionalAttrs (cfg.locationEnvFile != null) {
            EnvironmentFile = cfg.locationEnvFile;
          }
          // {
            # pkgs.dump1090-fa's actual binary is named dump1090 (confirmed
            # live: bin/ contains dump1090, faup1090, view1090 — no
            # dump1090-fa). The wrong name here made the service fail at
            # exec() itself (systemd status 203/EXEC) before any of its own
            # code ever ran.
            #
            # This build has no built-in HTTP server (confirmed via --help:
            # only raw/Beast/SBS TCP ports and --write-json, which its own
            # help text says is "for serving by a separate webserver"). Write
            # aircraft.json here so nginx (below) can serve it alongside the
            # skyaware static assets the package already ships.
            #
            # Wrapped in bash -c so --lat/--lon can be filled in from
            # $LOCATION_LAT/$LOCATION_LON (via EnvironmentFile above) rather
            # than baked into the Nix store as plain option values.
            # --json-location-accuracy 1 rounds the coordinates exposed in
            # aircraft.json itself (this is served publicly through Traefik)
            # while --lat/--lon stay full precision for range-ring math.
            ExecStart = "${pkgs.bash}/bin/bash -c 'exec ${pkgs.dump1090-fa}/bin/dump1090 --device-index ${cfg.device} --net --write-json /var/lib/dump1090 --write-json-every 1 ${lib.optionalString (cfg.locationEnvFile != null) ''--lat "$LOCATION_LAT" --lon "$LOCATION_LON" --json-location-accuracy 1''}'";
            Restart = "on-failure";
            User = "dump1090";
            Group = "dump1090";
            StateDirectory = "dump1090";
            # 0755 (not the 0750 default) so nginx, a separate unrelated
            # user, can read aircraft.json.
            StateDirectoryMode = "0755";
          };
      };

      # Static skyaware web UI. Confirmed live via `find` on the actual
      # store path that this package installs straight to share/dump1090
      # (index.html, script.js, ol/, etc.) — no public_html subdirectory,
      # unlike the nixpkgs revision this was first written against.
      # Serves the aircraft.json dump1090 writes to /var/lib/dump1090 via
      # --write-json above. No custom web server code — this is nginx
      # serving files that already exist, the same pattern FlightAware's
      # own packaging uses (lighttpd in that case).
      services.nginx = {
        enable = true;
        virtualHosts.dump1090 = {
          listen = [
            {
              addr = "127.0.0.1";
              port = 8080;
            }
          ];
          root = "${pkgs.dump1090-fa}/share/dump1090";
          locations."/data/".alias = "/var/lib/dump1090/";
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
