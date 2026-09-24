# Bambuddy: self-hosted Bambu Lab printer management, plus the optional
# server-side slicing sidecars it talks to.
#
# The app runs natively (pkgs/bambuddy.nix); the slicers can't --
# `maziggy/orca-slicer-api` wraps a patched OrcaSlicer CLI that only exists
# inside its own prebuilt image, no published source, no local build path.
# So this module is two shapes at once: a systemd unit plus oci-containers,
# same as modules/dcs-server.nix.
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) literalExpression mkEnableOption mkIf mkMerge mkOption types;
  mkTraefikRoute = import ../lib/traefik-route.nix;
  cfg = config.custom.bambuddy;
  sidecar = cfg.slicerSidecar;

  # StateDirectory=/LogsDirectory= own these, not options -- systemd's names
  # are relative; an absolute override needs a different, hand-managed mechanism.
  dataDir = "/var/lib/bambuddy";
  logDir = "/var/log/bambuddy";

  # What the virtual printer listens on (upstream's docker-compose.yml); 8000
  # is absent -- that goes through Traefik. Each VP gets a 10-port FTP slice.
  passiveFtpTo = 50000 + (10 * cfg.virtualPrinter.count) - 1;
  vpMultiport = "322,990,3000,3002,6000,8883,2024:2026,50000:${toString passiveFtpTo}";
in {
  options.custom.bambuddy = {
    enable = mkEnableOption "Bambuddy, self-hosted Bambu Lab printer management";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ../pkgs/bambuddy.nix {};
      defaultText = literalExpression "pkgs.callPackage ../pkgs/bambuddy.nix {}";
      description = "The Bambuddy package to run (backend, built frontend, and the uvicorn wrapper).";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address the web UI binds to. Loopback by default because Traefik fronts it; widen only for a host with no reverse proxy.";
    };

    port = mkOption {
      type = types.port;
      default = 8000;
      description = "Web UI / REST API port, and the only port routed through Traefik.";
    };

    virtualPrinter = {
      # The virtual printer emulates a Bambu printer so a slicer can "send to
      # printer" into Bambuddy. Its listeners are always started by the app;
      # this only controls the host firewall, since the ports have to be
      # reachable from the slicer and the real printers on the LAN rather than
      # through Traefik.
      openFirewall = mkEnableOption "the virtual printer's LAN ports in the host firewall (bind/detect, MQTT, FTPS, RTSP, and the FTP passive-data range), on bindIp only";

      bindIp = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "192.168.20.31";
        description = "The address the virtual printer is configured to bind in Bambuddy, and the only one openFirewall opens these ports on. Adding it to the interface is the host's job.";
      };

      count = mkOption {
        type = types.ints.positive;
        default = 3;
        description = "How many virtual printers to size the FTP passive-data port range for; each gets a 10-port slice from 50000 upward. Only used when openFirewall is set.";
      };
    };

    slicerSidecar = {
      # Defaults on with the parent: server-side slicing is the reason to run a
      # sidecar at all, and the container is inert until Bambuddy calls it.
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Run the OrcaSlicer slicing sidecar (prebuilt linux/amd64 OCI image under podman) alongside Bambuddy.";
      };

      image = mkOption {
        type = types.str;
        default = "ghcr.io/maziggy/orca-slicer-api:latest";
        description = "Fully-qualified OCI image reference for the OrcaSlicer sidecar. linux/amd64 only upstream — OrcaSlicer's ARM64 image is on hold pending an upstream extraction fix.";
      };

      port = mkOption {
        type = types.port;
        default = 3003;
        description = "Host port for the OrcaSlicer sidecar, bound to loopback only. 3003 rather than 3000 because Bambuddy's own virtual printer reserves 3000 and 3002.";
      };

      dataDir = mkOption {
        type = types.str;
        default = "/var/lib/bambuddy-slicer-orca";
        description = "Host directory bind-mounted to /app/data in the OrcaSlicer sidecar (resolved profiles and slice scratch space).";
      };

      maxModelUploadMb = mkOption {
        type = types.ints.positive;
        default = 512;
        description = "MAX_MODEL_UPLOAD_MB: largest model, in MB, either sidecar accepts for a slice.";
      };

      bambuStudio = {
        # Upstream gates this behind a compose profile (`--profile bambu`) and
        # leaves it off; it is a second, larger image serving the same API
        # with the BambuStudio CLI behind it. Assertion below covers the
        # port collision on reliant.
        enable = mkEnableOption "a second slicing sidecar backed by the BambuStudio CLI";

        image = mkOption {
          type = types.str;
          default = "ghcr.io/maziggy/bambu-studio-api:latest";
          description = "Fully-qualified OCI image reference for the BambuStudio sidecar. linux/amd64 only — upstream publishes no ARM64 build at all.";
        };

        port = mkOption {
          type = types.port;
          default = 3001;
          description = "Host port for the BambuStudio sidecar, bound to loopback only.";
        };

        dataDir = mkOption {
          type = types.str;
          default = "/var/lib/bambuddy-slicer-bambu";
          description = "Host directory bind-mounted to /app/data in the BambuStudio sidecar.";
        };
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          # Hardcoded in backend/app/services/virtual_printer/bind_server.py
          # — not configurable on either side.
          assertion =
            !cfg.virtualPrinter.openFirewall
            || !(config.services.adguardhome.enable && config.services.adguardhome.port == 3000);
          message = "custom.bambuddy.virtualPrinter.openFirewall conflicts with AdGuard Home on port 3000: Bambuddy's virtual printer binds 3000/3002 unconditionally and those ports are not configurable. Move AdGuard's admin UI (services.adguardhome.port) first.";
        }

        {
          # Without it the rule renders `-d ` and fails firewall.service at
          # runtime, which leaves the host with no INPUT jump to nixos-fw.
          assertion = !cfg.virtualPrinter.openFirewall || cfg.virtualPrinter.bindIp != null;
          message = "custom.bambuddy.virtualPrinter.openFirewall needs virtualPrinter.bindIp — the rules are scoped to that address, so there is nothing to open without it.";
        }

        {
          # Same class of collision, one option group down: bambuStudio.port
          # defaults to 3001, also custom.zwave.port's value on reliant (see
          # hosts/reliant/configuration.nix). Both are configurable, unlike
          # the virtual printer's, so this is a hard assertion, not an
          # off-by-default workaround.
          assertion =
            !(sidecar.enable && sidecar.bambuStudio.enable)
            || !(config.custom.zwave.enable && config.custom.zwave.port == sidecar.bambuStudio.port);
          message = "custom.bambuddy.slicerSidecar.bambuStudio.port (${toString sidecar.bambuStudio.port}) collides with custom.zwave.port on this host. Set a different custom.bambuddy.slicerSidecar.bambuStudio.port.";
        }
      ];

      # A fixed system user, not DynamicUser: the data directory holds a
      # print archive worth reading/copying over SSH without going through
      # /var/lib/private (root-only) -- same reasoning as modules/adsb.nix.
      users = {
        users.bambuddy = {
          isSystemUser = true;
          group = "bambuddy";
          home = dataDir;
        };
        groups.bambuddy = {};
      };

      systemd.services.bambuddy = {
        description = "Bambuddy Bambu Lab print management";
        documentation = ["https://github.com/maziggy/bambuddy"];
        wantedBy = ["multi-user.target"];
        after = ["network.target"];

        # network_utils.py shells to `ip -j addr show` for secondary
        # addresses; missing it, a silent ioctl fallback returns only the
        # primary IP, so the bind IP never appears in the UI. Its own
        # fallback PATH (/usr/sbin:/sbin:/usr/bin:/bin) finds nothing here.
        path = [pkgs.iproute2];

        environment = {
          # backend/app/core/config.py reads both; without them it falls back
          # to paths relative to the (read-only) store copy of the app.
          DATA_DIR = dataDir;
          LOG_DIR = logDir;
          TZ = config.time.timeZone;
          # getpass.getuser()/os.path.expanduser() are called by asyncssh and
          # friends; systemd sets no HOME for a system unit.
          HOME = dataDir;
          # matplotlib (STL thumbnail generator) builds a font cache under
          # $HOME/.config/matplotlib on first import, else re-scans every
          # font every restart from a fresh temp dir. Upstream's image pins
          # /tmp for the same reason; this keeps the cache across restarts.
          MPLCONFIGDIR = "${dataDir}/matplotlib";
        };

        serviceConfig = {
          # --loop asyncio: required, not a preference -- uvloop truncates
          # virtual-printer FTP uploads (upstream issue #1896); upstream's own
          # unit and Dockerfile both pass it despite shipping uvicorn[standard].
          # --timeout-graceful-shutdown: without it, an open MJPEG camera tile
          # hangs every stop until SIGKILL, skipping the WAL checkpoint and
          # virtual-printer teardown.
          ExecStart = "${cfg.package}/bin/bambuddy --host ${cfg.listenAddress} --port ${toString cfg.port} --loop asyncio --timeout-graceful-shutdown 5";
          User = "bambuddy";
          Group = "bambuddy";
          Restart = "on-failure";
          RestartSec = 5;
          # Backstop only — uvicorn bounds its own wait at 5s above.
          TimeoutStopSec = 30;

          StateDirectory = "bambuddy";
          StateDirectoryMode = "0750";
          LogsDirectory = "bambuddy";

          # Binds 322 (RTSPS) and 990 (FTPS) as non-root. Upstream's image
          # uses setcap + docker's cap_add; this is the native equivalent,
          # bounded to just this one capability.
          AmbientCapabilities = ["CAP_NET_BIND_SERVICE"];
          CapabilityBoundingSet = ["CAP_NET_BIND_SERVICE"];

          NoNewPrivileges = true;
          PrivateTmp = true;
          # State/LogsDirectory stay writable under strict; nothing else
          # needs to be -- the app lives in the store, self-update inert.
          ProtectSystem = "strict";
          ProtectHome = true;
        };
      };

      # Destination-scoped, not allowedTCPPorts (matches on port alone,
      # opening these on every address -- AdGuard's admin UI among them).
      # firewall-start rebuilds nixos-fw, so no extraStopCommands.
      networking.firewall.extraCommands = mkIf cfg.virtualPrinter.openFirewall ''
        iptables -I nixos-fw -p tcp -d ${cfg.virtualPrinter.bindIp} -m multiport --dports ${vpMultiport} -j ACCEPT
      '';
    }

    (mkIf sidecar.enable {
      # oci-containers enables podman itself, no profiles/dev import needed.
      virtualisation.oci-containers = {
        backend = "podman";

        containers.orca-slicer-api = {
          inherit (sidecar) image;
          autoStart = true;

          environment = {
            NODE_ENV = "production";
            PORT = "3000";
            MAX_MODEL_UPLOAD_MB = toString sidecar.maxModelUploadMb;
          };

          volumes = ["${sidecar.dataDir}:/app/data"];

          # Loopback only: an internal API Bambuddy calls on the same host,
          # not human-browsed -- no Traefik route, no firewall opening.
          ports = ["127.0.0.1:${toString sidecar.port}:3000/tcp"];
        };
      };

      systemd.tmpfiles.rules = ["d ${sidecar.dataDir} 0755 root root -"];

      # A URL set in Settings → Slicer wins over this; with it, nothing to
      # configure by hand, following `port` over the compiled-in default.
      systemd.services.bambuddy.environment.SLICER_API_URL = "http://127.0.0.1:${toString sidecar.port}";
    })

    (mkIf (sidecar.enable && sidecar.bambuStudio.enable) {
      virtualisation.oci-containers.containers.bambu-studio-api = {
        inherit (sidecar.bambuStudio) image;
        autoStart = true;

        environment = {
          NODE_ENV = "production";
          PORT = "3000";
          MAX_MODEL_UPLOAD_MB = toString sidecar.maxModelUploadMb;
        };

        volumes = ["${sidecar.bambuStudio.dataDir}:/app/data"];
        ports = ["127.0.0.1:${toString sidecar.bambuStudio.port}:3000/tcp"];
      };

      systemd.tmpfiles.rules = ["d ${sidecar.bambuStudio.dataDir} 0755 root root -"];

      systemd.services.bambuddy.environment.BAMBU_STUDIO_API_URL = "http://127.0.0.1:${toString sidecar.bambuStudio.port}";
    })

    # Self-register Traefik route
    (mkIf config.custom.traefik.enable {
      services.traefik.dynamicConfigOptions.http = mkTraefikRoute {
        name = "bambuddy";
        inherit (cfg) port;
        inherit (config.custom.traefik.acme) domain;
      };
    })
  ]);
}
