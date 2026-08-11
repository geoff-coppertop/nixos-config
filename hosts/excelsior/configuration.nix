_: let
  nas = import ../../lib/nas.nix;
  thomasga = import ../../users/thomasga/account.nix;
in {
  imports = [
    ./secrets.nix
    ./hardware.nix
    ./disko.nix

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

        # This host's own independent DNS instance (custom.dns below) runs
        # AdGuard Home — same job every other AdGuard-running host
        # (defiant, reliant) already backs up. Job-keyed, not machine-keyed
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

      # Headless server, so nothing binds this to Traefik locally; the
      # fleet's Traefik host (reliant) proxies it cross-VLAN by static IP
      # instead (see its proxiedRemotes).
      backrest = {
        enable = true;
        listenAddress = "0.0.0.0";
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
      # also defaults to 3000 and is what defiant's dns2.coppertop.ca
      # Traefik route depends on (hosts/defiant/configuration.nix) — same
      # class of conflict defiant already hit and fixed for zwave-js.
      desktopPort = 3001;
    };

    dns = {
      enable = true;
      domain = "coppertop.ca";
      lanIp = "192.168.1.10";
      # Module default (192.168.1.0/24) is narrower than the actual network:
      # 3 VLANs, all 192.168.x.0/24. Widened to match defiant's override so
      # direct (bypass) queries on port 5335 work from any of them.
      lanSubnet = "192.168.0.0/16";
      # No custom.traefik here: Traefik stays single-instance on defiant,
      # which proxies this host's AdGuard admin UI cross-host (see
      # hosts/defiant/configuration.nix's dns2 router).
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

  networking.hostName = "excelsior";
  networking.hosts.${nas.ip} = [nas.host];
  system.stateVersion = "25.11";
}
