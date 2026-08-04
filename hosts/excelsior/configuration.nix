_: let
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
  system.stateVersion = "25.11";
}
