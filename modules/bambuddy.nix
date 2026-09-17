# Bambuddy: self-hosted management, archive, and print queue for Bambu Lab
# printers, plus the optional server-side slicing sidecars it talks to.
#
# The app runs natively (pkgs/bambuddy.nix); the slicers do not, and cannot —
# `maziggy/orca-slicer-api` is a Node HTTP wrapper around a *patched*
# OrcaSlicer CLI that only exists inside its own prebuilt image, with no
# published source or local build path. So this module is deliberately two
# shapes at once: a systemd unit for Bambuddy, oci-containers for the
# slicers, same as modules/dcs-server.nix runs the DCS image.
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

  # StateDirectory=/LogsDirectory= own these; they are not options, because
  # systemd's directory names are relative by definition and an absolute
  # override would need a different (unprivileged, hand-managed) mechanism.
  dataDir = "/var/lib/bambuddy";
  logDir = "/var/log/bambuddy";

  # Virtual-printer FTP passive-data ports. Upstream allocates a 10-port slice
  # per virtual printer starting at 50000 (VP 1 → 50000-50009, VP 2 →
  # 50010-50019, …), so the range is sized by the VP count rather than opening
  # the full 50000-50100 the Bambu firmware itself uses.
  passiveFtp = {
    from = 50000;
    to = 50000 + (10 * cfg.virtualPrinter.count) - 1;
  };
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
      openFirewall = mkEnableOption "the virtual printer's LAN ports in the host firewall (bind/detect, MQTT, FTPS, RTSP, and the FTP passive-data range)";

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
        # leaves it off; it is a second, larger image serving the same API with
        # the BambuStudio CLI behind it. NOTE for any host that turns this on:
        # port 3001 is already taken by zwave-js on reliant
        # (modules/zwave.nix's own default was moved off 3000 for the same
        # kind of collision) — set `port` explicitly there.
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
          # 3000/3002 are hardcoded constants in
          # backend/app/services/virtual_printer/bind_server.py — not
          # configurable on either side. AdGuard Home's admin UI defaults to
          # 3000 too (modules/dns.nix), making the two mutually exclusive on
          # one host until AdGuard is moved.
          assertion =
            !cfg.virtualPrinter.openFirewall
            || !(config.services.adguardhome.enable && config.services.adguardhome.port == 3000);
          message = "custom.bambuddy.virtualPrinter.openFirewall conflicts with AdGuard Home on port 3000: Bambuddy's virtual printer binds 3000/3002 unconditionally and those ports are not configurable. Move AdGuard's admin UI (services.adguardhome.port) first.";
        }

        {
          # Same class of collision, one group down: sidecar.bambuStudio.port
          # defaults to 3001, also custom.zwave.port's value on reliant
          # (moved there to dodge the AdGuard/3000 collision — see
          # modules/zwave.nix). Both ports are configurable here, so this is
          # a hard assertion — nothing else would catch a later
          # bambuStudio.enable flip hitting EADDRINUSE.
          assertion =
            !(sidecar.enable && sidecar.bambuStudio.enable)
            || !(config.custom.zwave.enable && config.custom.zwave.port == sidecar.bambuStudio.port);
          message = "custom.bambuddy.slicerSidecar.bambuStudio.port (${toString sidecar.bambuStudio.port}) collides with custom.zwave.port on this host. Set a different custom.bambuddy.slicerSidecar.bambuStudio.port.";
        }
      ];

      # Fixed system user, not DynamicUser: the data directory holds a
      # person's print archive and 3MF library, worth reading/copying over
      # SSH without going through root-only /var/lib/private (same reasoning
      # as modules/adsb.nix).
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

        environment = {
          # backend/app/core/config.py reads both; without them it falls back
          # to paths relative to the (read-only) store copy of the app.
          DATA_DIR = dataDir;
          LOG_DIR = logDir;
          TZ = config.time.timeZone;
          # getpass.getuser()/os.path.expanduser() are called by asyncssh and
          # friends; systemd sets no HOME for a system unit.
          HOME = dataDir;
          # matplotlib (lazily imported by the STL thumbnail generator)
          # builds a font cache under $HOME/.config/matplotlib on first
          # import, falling back to a fresh temp dir (re-scanning every font
          # every restart) if it can't write there. The state directory
          # keeps the cache across restarts instead.
          MPLCONFIGDIR = "${dataDir}/matplotlib";
        };

        serviceConfig = {
          # --loop asyncio is required, not a preference: uvloop truncates
          # virtual-printer FTP uploads (upstream issue #1896).
          #
          # --timeout-graceful-shutdown likewise: uvicorn otherwise waits
          # forever for in-flight requests, and an open MJPEG camera stream
          # never completes, hanging every stop until systemd SIGKILLs —
          # skipping the SQLite WAL checkpoint and MQTT/virtual-printer
          # teardown.
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

          # The virtual printer binds 322 (RTSPS camera proxy) and 990 (FTPS
          # control) as a non-root user — an ambient capability, bounded to
          # just that one, is the native equivalent of upstream's setcap.
          AmbientCapabilities = ["CAP_NET_BIND_SERVICE"];
          CapabilityBoundingSet = ["CAP_NET_BIND_SERVICE"];

          NoNewPrivileges = true;
          PrivateTmp = true;
          # StateDirectory/LogsDirectory stay writable under strict; nothing
          # else needs to be, since the app lives in the store and its
          # self-update path is inert without a .git alongside it.
          ProtectSystem = "strict";
          ProtectHome = true;
        };
      };

      networking.firewall = mkIf cfg.virtualPrinter.openFirewall {
        # From upstream's docker-compose.yml: 3000/3002 bind+detect, 8883
        # MQTT, 990 FTPS control, 6000 file-transfer tunnel, 322 RTSPS
        # camera, 2024-2026 the A1/P1S protocol, plus the passive-data range
        # above. 8000 is deliberately absent — that one goes through Traefik.
        allowedTCPPorts = [322 990 3000 3002 6000 8883];
        allowedTCPPortRanges = [
          {
            from = 2024;
            to = 2026;
          }
          passiveFtp
        ];
      };
    }

    (mkIf sidecar.enable {
      # oci-containers enables podman itself; no profiles/dev import needed
      # (same as hosts/excelsior/configuration.nix).
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

          # Loopback only: this is an internal API Bambuddy calls on the same
          # host, not something a human browses, so it gets no Traefik route
          # and no firewall opening.
          ports = ["127.0.0.1:${toString sidecar.port}:3000/tcp"];
        };
      };

      systemd.tmpfiles.rules = ["d ${sidecar.dataDir} 0755 root root -"];

      # A URL set in Settings → Slicer wins over this, but with it there is
      # nothing to configure by hand — and it keeps following the `port`
      # option instead of the app's compiled-in localhost:3003 default.
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

    (mkIf config.custom.traefik.enable {
      services.traefik.dynamicConfigOptions.http = mkTraefikRoute {
        name = "bambuddy";
        inherit (cfg) port;
        inherit (config.custom.traefik.acme) domain;
      };
    })
  ]);
}
