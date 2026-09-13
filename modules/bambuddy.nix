# Bambuddy: self-hosted management, archive, and print queue for Bambu Lab
# printers, plus the optional server-side slicing sidecars it talks to.
#
# The app itself runs natively (pkgs/bambuddy.nix); the slicers do not, and
# cannot — `maziggy/orca-slicer-api` is a Node HTTP wrapper around a *patched*
# OrcaSlicer CLI binary that only exists inside its own prebuilt image, with no
# published source for the patches and no local build path. So this module is
# deliberately two shapes at once: a systemd unit for Bambuddy and
# oci-containers for the slicers, the same way modules/dcs-server.nix runs the
# DCS image.
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) concatStringsSep filter hasInfix literalExpression mkEnableOption mkIf mkMerge mkOption types unique;
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

  # What the virtual printer actually listens on, from upstream's
  # docker-compose.yml: 3000/3002 bind+detect, 8883 MQTT, 990 FTPS control,
  # 6000 file-transfer tunnel, 322 RTSPS camera, 2024-2026 the A1/P1S
  # proprietary protocol, plus the passive-data range above. Port 8000 is
  # deliberately absent — that one goes through Traefik.
  vpPorts = [322 990 3000 3002 6000 8883];
  vpPortRanges = [
    {
      from = 2024;
      to = 2026;
    }
    passiveFtp
  ];

  # `-m multiport --dports` holds at most 15 port slots and spends two of them
  # on a range (XT_MULTI_PORTS in include/uapi/linux/netfilter/xt_multiport.h;
  # net/netfilter/xt_multiport.c reads a range as two consecutive entries), so
  # this set costs 6 + 2*2 = 10 and the whole opening is one rule per address.
  # Six more ports, or a third range plus two, would not fit and would have to
  # be split across rules.
  vpMultiport = concatStringsSep "," (
    map toString vpPorts
    ++ map (r: "${toString r.from}:${toString r.to}") vpPortRanges
  );

  # The addresses the enabled virtual printers bind. `virtualPrinters` is
  # declared in modules/bambuddy-provision.nix — a different file, the same
  # custom.bambuddy namespace, so it is readable from the same `config`.
  # bindIp is never null on an enabled entry: upstream's
  # POST /virtual-printers rejects `enabled: true` without one ("Bind IP is
  # required when enabling"), and bambuddy-provision.nix asserts it at eval
  # time, so filtering on it here drops nothing that would ever listen.
  bindingVps = filter (vp: vp.enabled && vp.bindIp != null) cfg.virtualPrinters;
  vpBindIps = unique (map (vp: vp.bindIp) bindingVps);

  # One destination-scoped ACCEPT per bind address, rather than
  # allowedTCPPorts/allowedTCPPortRanges — those match on port alone and so
  # open these holes on *every* address the host carries, including its
  # primary LAN address where nothing serves them. Port 3000 makes the
  # difference concrete: AdGuard Home's admin UI is deliberately not
  # firewall-opened on this host and binds 0.0.0.0 by default, so a
  # port-only rule would publish it to the LAN the moment it moved back to
  # its own default port.
  #
  # Same shape as the Home Assistant 8123 rule in
  # hosts/reliant/configuration.nix, scoped by destination (-d) instead of
  # source (-s). The backend is iptables (nothing in this repo sets
  # networking.nftables.enable or networking.firewall.backend, and the
  # backend option defaults to iptables unless one of those is set), which is
  # what makes `nixos-fw` the chain to insert into. ip6tables for a v6 bind
  # address: iptables would reject it at runtime and fail firewall.service,
  # which leaves the host with no INPUT jump to nixos-fw at all.
  #
  # No matching extraStopCommands, deliberately, and not just by analogy with
  # the 8123 rule: firewall-start deletes and recreates nixos-fw before it
  # does anything else (nixos/modules/services/networking/firewall-iptables.nix),
  # and both start and reload run that script, so a rule living in nixos-fw
  # is torn down for free. extraStopCommands is for rules put somewhere the
  # start script does not rebuild — INPUT itself, FORWARD, the nat table.
  iptablesFor = ip:
    if hasInfix ":" ip
    then "ip6tables"
    else "iptables";

  vpRule = ip: "${iptablesFor ip} -I nixos-fw -p tcp -d ${ip} -m multiport --dports ${vpMultiport} -j ACCEPT";

  vpFirewallRules = concatStringsSep "\n" (map vpRule vpBindIps);

  # AdGuard Home's admin listener overlaps a virtual printer's bind address
  # when it is on 3000 and bound either to a wildcard or to that exact
  # address; see the assertion below for what that costs. host defaults to
  # "0.0.0.0" and port to 3000 in the nixpkgs module.
  adguard = config.services.adguardhome;
  adguardOverlapsVp =
    adguard.enable
    && adguard.port == 3000
    && builtins.elem adguard.host (["0.0.0.0" "::" ""] ++ vpBindIps);
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
      openFirewall = mkEnableOption "the virtual printer's LAN ports in the host firewall (bind/detect, MQTT, FTPS, RTSP, and the FTP passive-data range), on the bindIp of each enabled custom.bambuddy.virtualPrinters entry and on no other address the host carries. Asserts if no enabled virtual printer is declared, since there would be no address to scope to";

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
          # openFirewall's rules are scoped to the bind addresses above, so
          # with none there is nothing to write. Asserting rather than
          # falling back to host-wide allowedTCPPorts: the fallback is the
          # exact behaviour this scoping replaced, and it would come back
          # silently, on the host with the fewest reasons to want it. Nor is
          # emitting nothing right — that is a virtual printer that looks
          # healthy and refuses every connection, which
          # modules/bambuddy-provision.nix already warns about from the other
          # direction.
          assertion = !cfg.virtualPrinter.openFirewall || vpBindIps != [];
          message = "custom.bambuddy.virtualPrinter.openFirewall is set, but no entry in custom.bambuddy.virtualPrinters has both enabled = true and a bindIp, so there is no address to open the ports on. Declare the virtual printer (its bindIp is the address a slicer points at), or turn openFirewall off.";
        }

        {
          # Ports 3000 and 3002 are hardcoded constants in
          # backend/app/services/virtual_printer/bind_server.py — a slicer
          # looks for a printer on exactly those ports, so they are not
          # configurable on either side. AdGuard Home's admin UI defaults to
          # 3000 and modules/dns.nix keeps that default.
          #
          # Scoping the firewall rules to bindIp narrows this collision but
          # does not remove it, so the assertion stays — retargeted from
          # "openFirewall is on" to what actually overlaps. AdGuard binds
          # services.adguardhome.host, 0.0.0.0 by default, and a wildcard
          # bind covers every bindIp: AdGuard starting first leaves Bambuddy
          # logging "Bind server port 3000 already in use, skipping" (see
          # hosts/reliant/README.md § Known Gotchas — it keeps serving 3002
          # rather than crashing), so a slicer never finds the printer, and
          # with openFirewall on the rule written above then points at
          # AdGuard's admin UI instead. AdGuard bound to one specific address
          # that is not a bindIp genuinely does not collide, and no longer
          # trips this.
          assertion = vpBindIps == [] || !adguardOverlapsVp;
          message = "custom.bambuddy.virtualPrinters declares an enabled virtual printer while AdGuard Home serves its admin UI on port 3000 at an address that covers the virtual printer's bindIp (services.adguardhome.host = \"${adguard.host}\"). Bambuddy binds 3000/3002 unconditionally and those ports are not configurable, so its bind server skips 3000 and no slicer finds the printer — and with virtualPrinter.openFirewall set, AdGuard's admin UI becomes what answers on the bind address instead. Move AdGuard's admin UI (services.adguardhome.port) first.";
        }

        {
          # Same class of collision as the one above, one option group down:
          # sidecar.bambuStudio.port defaults to 3001, which is also
          # custom.zwave.port's value on reliant (moved there itself to dodge
          # the AdGuard/3000 collision — see modules/zwave.nix). Both ports
          # are configurable here, unlike the virtual printer's, so this is a
          # hard assertion rather than an off-by-default workaround: nothing
          # stops someone flipping bambuStudio.enable on later and hitting
          # EADDRINUSE with no other signal.
          assertion =
            !(sidecar.enable && sidecar.bambuStudio.enable)
            || !(config.custom.zwave.enable && config.custom.zwave.port == sidecar.bambuStudio.port);
          message = "custom.bambuddy.slicerSidecar.bambuStudio.port (${toString sidecar.bambuStudio.port}) collides with custom.zwave.port on this host. Set a different custom.bambuddy.slicerSidecar.bambuStudio.port.";
        }
      ];

      # A fixed system user, not DynamicUser: the data directory holds a
      # person's print archive and 3MF library, which is worth being able to
      # read and copy over SSH without going through /var/lib/private (which
      # is root-only, see the same reasoning in modules/adsb.nix).
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
          # matplotlib (lazily imported by the STL thumbnail generator) builds
          # a font cache under $HOME/.config/matplotlib on first import and
          # falls back to a fresh temp dir — re-scanning every font on every
          # restart — if it cannot write there. Upstream's image pins it to
          # /tmp for the same reason; the state directory keeps the cache
          # across restarts instead.
          MPLCONFIGDIR = "${dataDir}/matplotlib";
        };

        serviceConfig = {
          # --loop asyncio is required, not a preference: uvloop truncates
          # virtual-printer FTP uploads (upstream issue #1896), which is why
          # upstream's own generated unit and Dockerfile both pass it despite
          # shipping uvicorn[standard].
          #
          # --timeout-graceful-shutdown likewise: uvicorn otherwise waits
          # forever for in-flight requests, and an MJPEG camera stream never
          # completes, so one open camera tile would hang every stop until
          # systemd SIGKILLs — skipping the SQLite WAL checkpoint and the
          # MQTT/virtual-printer teardown.
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
          # control) as a non-root user. Upstream's image gets this with
          # setcap on the interpreter plus docker's cap_add; the native
          # equivalent is an ambient capability, bounded to just that one.
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

      # Destination-scoped, not allowedTCPPorts — see vpFirewallRules above
      # for why, for the multiport budget, and for why there is no
      # extraStopCommands. The source address is deliberately left open: a
      # slicer or a real printer can sit anywhere the bind address is
      # routable, and a host wanting a narrower source can add its own rule
      # the way hosts/reliant/configuration.nix does for 8123.
      networking.firewall.extraCommands = mkIf cfg.virtualPrinter.openFirewall ''
        ${vpFirewallRules}
      '';
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
