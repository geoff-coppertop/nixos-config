{
  config,
  lib,
  pkgs,
  ...
}: let
  nas = import ../../lib/nas.nix;
  thomasga = import ../../users/thomasga/account.nix;
in {
  imports = [
    ./secrets.nix
    ./hardware.nix
    ./disko.nix
    ./media.nix

    ../../profiles/common
    # NOT: profiles/desktop — no display server
    # NOT: profiles/dev — no devcontainer tooling; oci-containers enables podman itself

    ../../modules
  ];

  custom = {
    users.thomasga =
      thomasga
      // {
        groups = ["wheel"];
        avatar = null;
      };

    btrfs.enable = true;
    snapper.enable = true;

    backups = {
      enable = true;

      nas = {
        # Reuses the shared thomasga/nas-smb-credentials secret rather than
        # minting a new one — every host mounts the same NAS (lib/nas.nix),
        # so there's no reason for per-host SMB credentials. Matches
        # enterprise-d/reliant's precedent, not a prior version of this
        # file's own separate excelsior-only secret (that was the gap
        # reliant's own comment already flagged as not the pattern to copy).
        credentialsFile = "/run/agenix/thomasga/nas-smb-credentials";
        inherit (nas) host;
        share = nas.shares.backups;
      };

      users = {
        # Consistency with the rest of the fleet (enterprise-d, holodeck-01,
        # reliant all back up thomasga's home dir), even though this is a
        # headless server thomasga rarely touches directly. Reuses the
        # existing shared thomasga/restic-password secret rather than
        # minting a new one — same job-keyed pattern as adguardhome below.
        thomasga.enable = true;

        dcs-server = {
          enable = true;
          # Confirmed live on the first deploy: backing up the whole dataDir
          # (as a fail-safe, before this path was known) produced a 52.7 GiB
          # snapshot — almost all of it the re-downloadable DCS install and
          # wine prefix, not anything irreplaceable. The wine container's
          # actual user is "abc" (LinuxServer.io convention, not "root"), and
          # DCS names its Saved Games profile "DCS.dcs_serverrelease", not
          # the generic "DCS.server" this path originally guessed — real
          # size confirmed live at 184K (config, logs, persistence,
          # logbook.db; no Missions pushed yet, but future mission files
          # land inside this same directory and are covered by it).
          paths = [
            "/var/lib/dcs-server/.wine/drive_c/users/abc/Saved Games/DCS.dcs_serverrelease"
            "/var/lib/dcs-srs-server/Presets"
          ];
          excludePatterns = [];
          passwordFile = "/run/agenix/dcs-server/restic-password";
        };

        factorio = {
          enable = true;
          # services.factorio's default state dir. DynamicUser makes it a
          # symlink into /var/lib/private, which modules/backups.nix's
          # readlink -f resolves before handing the path to restic.
          paths = ["/var/lib/factorio"];
          excludePatterns = [];
          passwordFile = "/run/agenix/factorio/restic-password";
        };

        # This host's own independent DNS instance (custom.dns below) runs
        # AdGuard Home — same job every other AdGuard-running host
        # (reliant) already backs up. Job-keyed, not machine-keyed
        # (docs/secrets.md § Secret Inventory): reuses the existing shared
        # adguardhome/restic-password secret rather than minting a new one,
        # same reasoning as reliant's hass/zigbee2mqtt/zwave-js jobs. Path
        # capitalized to match the confirmed-live symlink target on every
        # other host running AdGuard Home.
        adguardhome = {
          enable = true;
          paths = ["/var/lib/AdGuardHome"];
          excludePatterns = [];
        };
      };
    };

    dcsServer = {
      enable = true;
      # Login saved + auto-login enabled in the DCS launcher (confirmed live:
      # the container starts straight into a running session with no login
      # prompt), so the server can launch unattended with the container.
      autoStart = true;
      # DCS is fully installed and up to date. Confirmed live: leaving this
      # at the module default (true) re-runs DCS_updater.exe on every
      # restart, and its "Nothing to install" result pops up a GUI dialog
      # that blocks indefinitely with nobody there to click OK -- autoStart
      # never reaches DCS_server.exe. Disabling it here skips the updater
      # entirely on restart, so autoStart is actually unattended. Flip back
      # to true (and click through the dialog once via the web desktop) to
      # pick up a DCS update, then back to false.
      autoInstall = false;
      srs.enable = true;
      # Module default (3000) collides with AdGuard Home's admin UI, which
      # also defaults to 3000 and is what reliant's dns2.coppertop.ca
      # Traefik route depends on (hosts/reliant/configuration.nix) — same
      # class of conflict reliant already hit and fixed for zwave-js.
      desktopPort = 3001;
      # Bound to this host's own LAN IP so the router's WAN port-forward
      # (8088, alongside the game port 10308 — router-side config, not
      # managed by this repo) has something to actually reach. DCS's own
      # remote-control mechanism assumes this port is directly
      # port-forwarded from the WAN, no HTTP-layer proxy in the path — a
      # same-origin Traefik/nginx reverse proxy was tried and confirmed
      # live NOT to work (DCS deliberately rejects WebGUI API calls that
      # don't arrive from a genuinely local connection, by design — see
      # this README's Known Gotchas). openFirewall below opens this
      # broadly, same as the game port, since real remote DCS clients can
      # come from any public IP, not just reliant's.
      webGuiBindAddress = "192.168.1.10";
      # On-demand start/stop via dcs.coppertop.ca (see
      # docs/homelab-network.md) instead of always running. startAtBoot=false
      # means a reboot no longer brings DCS back up on its own — start it
      # through the control page.
      startAtBoot = false;
      control = {
        enable = true;
        bindAddress = "192.168.1.10";
      };
    };

    factorioServer.enable = true;

    dns = {
      enable = true;
      domain = "coppertop.ca";
      lanIp = "192.168.1.10";
      # Module default (192.168.1.0/24) is narrower than the actual network:
      # 3 VLANs, all 192.168.x.0/24. Widened to match reliant's override so
      # direct (bypass) queries on port 5335 work from any of them.
      lanSubnet = "192.168.0.0/16";
      # No custom.traefik here: Traefik stays single-instance on reliant,
      # which proxies this host's AdGuard admin UI cross-host (see
      # hosts/reliant/configuration.nix's dns2 router).
      #
      # This resolver otherwise knows nothing about the internal zone (no
      # subdomains of its own), which defeats the point of handing it out as
      # a DHCP-secondary alongside reliant's: if reliant's resolver were
      # down, none of these names would resolve here either. Mirror
      # reliant's own subdomains list so this resolver independently answers
      # for the whole zone too. Every entry points at reliant's IP, not this
      # host's own — even jellyfin, which physically runs here — because
      # reliant's Traefik is the sole public entrypoint for all of them (its
      # own subdomains list resolves the same names to itself for the same
      # reason), and excelsior's firewall only accepts these ports from
      # reliant in the first place (hosts/excelsior/media.nix and the
      # extraCommands block below). Keep in sync with
      # hosts/reliant/configuration.nix's subdomains list by hand — no
      # shared source of truth yet, to keep this change small.
      extraRecords = let
        reliantIp = "192.168.20.15";
      in {
        home = reliantIp;
        dns1 = reliantIp;
        dns2 = reliantIp;
        dcs = reliantIp;
        jellyfin = reliantIp;
        rip = reliantIp;
        library = reliantIp;
        adsb = reliantIp;
        zigbee = reliantIp;
        bambuddy = reliantIp;
      };
    };
  };

  # Headless — the only way in is SSH with an authorized key
  # (modules/users.nix's authorizedKeysFor), never a physical console.
  # That key check is the actual gate; a sudo password on top of it just
  # blocks unattended remote deploys (nixos-rebuild --target-host) without
  # adding real security.
  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    openFirewall = true;

    settings = {
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # custom.factorioServer is only an enable gate (see
  # modules/factorio-server.nix) — every actual setting goes straight to
  # services.factorio.* here.
  #
  # WAN-facing per the router port-forward noted below — access control is
  # the firewall (LAN/WAN, same posture as DCS's game port) plus a real
  # in-game password enforced via extraSettingsFile (agenix secret, see
  # Known Gotchas in this host's README); no factorio.com whitelist/admin
  # list configured yet.
  services.factorio = lib.mkIf config.custom.factorioServer.enable {
    openFirewall = true;
    extraSettingsFile = config.age.secrets."factorio/game-password".path;
    # Upstream defaults this to false; LAN discovery is the sane default for
    # a server WAN players only reach via direct-connect anyway (confirmed
    # live: server-settings.json otherwise ships visibility.lan=false and the
    # server never shows up in the in-game browser).
    lan = true;
    game-name = "CGWANO";
    description = "Cool Guys Who Are Not Old build factories";
    # Strips the Space Age expansion content so players without the DLC can
    # join — see Known Gotchas in this host's README for why this can't be
    # done through server-settings/mod-list.json instead. Appends to
    # installPhase, not postInstall: upstream's installPhase is a raw script
    # (mkdir/cp/patchelf) that never calls `runHook postInstall`, confirmed
    # live — a postInstall override silently never ran.
    package = pkgs.factorio-headless.overrideAttrs (old: {
      installPhase =
        old.installPhase
        + ''
          rm -rf $out/share/factorio/data/{space-age,quality,elevated-rails}
        '';
    });
  };

  # The DCS on-demand control page + webhook (custom.dcsServer.control,
  # 9090/9091) and AdGuard Home's admin UI (custom.dns, port 3000) are
  # bound to this host's own LAN IP rather than 127.0.0.1 or 0.0.0.0,
  # specifically so reliant's Traefik can reach them cross-host
  # (dcs.coppertop.ca, dns2.coppertop.ca) — neither has real auth of its
  # own at any layer yet (a holistic Traefik auth pass is a deliberate
  # follow-up), so the firewall is the only thing standing between them and
  # the whole LAN. Restricted to reliant's IP only, same pattern as
  # hosts/reliant/configuration.nix's own 8123 restriction.
  #
  # DCS's raw WebGUI backend (custom.dcsServer.webGuiPort, 8088) is
  # different: it's meant to be reached directly by real remote DCS
  # clients over the WAN (router port-forward, not managed by this repo —
  # see the webGuiBindAddress comment above), which can come from any
  # public IP, not just reliant's. Opened the same broad way as the game
  # port (10308, via custom.dcsServer.openFirewall) rather than restricted
  # to one source.
  networking = {
    firewall.allowedTCPPorts = [8088];

    firewall.extraCommands = ''
      iptables -I nixos-fw -p tcp -s 192.168.20.15 --dport 3000 -j ACCEPT
      iptables -I nixos-fw -p tcp -s 192.168.20.15 --dport 9090 -j ACCEPT
      iptables -I nixos-fw -p tcp -s 192.168.20.15 --dport 9091 -j ACCEPT
    '';

    hostName = "excelsior";
    hosts.${nas.ip} = [nas.host];
  };

  system.stateVersion = "25.11";
}
