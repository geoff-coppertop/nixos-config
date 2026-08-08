# Phase 1 (machine provisioning) only — see docs/provisioning.md § Two
# Phases. This host will eventually replace defiant as the homelab server,
# but no homelab/smart-home service module is enabled here. That migration
# is Phase 2, a separate PR owned by homelab-network and smart-home, opened
# only after this Phase 1 PR has merged and the machine is confirmed up per
# docs/provisioning.md § Step 7.
_: let
  nas = import ../../lib/nas.nix;
  thomasga = import ../../users/thomasga/account.nix;
in {
  imports = [
    ./secrets.nix
    ./hardware.nix
    ./power.nix
    ./disko.nix

    ../../profiles/common
    # NOT: profiles/desktop — no display server
    # NOT: profiles/dev — no devcontainer tooling; Phase 2 decides whether
    # this host needs it once its actual service set (migrated from
    # defiant) is known

    ../../modules
  ];

  custom = {
    users.thomasga =
      thomasga
      // {
        groups = ["wheel"];
        avatar = null;
      };

    # Matches enterprise-d's precedent, not excelsior's (excelsior lacking
    # backups is an existing gap there, not the pattern to copy). Reuses
    # enterprise-d's job-keyed "thomasga" secrets — restic-password and
    # nas-smb-credentials are keyed to the backup job name, not the
    # machine (docs/secrets.md § Secret Inventory), and the restic repo
    # path already includes the hostname, so sharing these secrets across
    # hosts doesn't collide their backup data.
    backups = {
      enable = true;

      nas = {
        credentialsFile = "/run/agenix/thomasga/nas-smb-credentials";
        inherit (nas) host;
        share = nas.shares.backups;
      };

      users.thomasga.enable = true;
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

  # ── Networking ────────────────────────────────────────────────────────────
  # Reserved LAN IP: 192.168.20.15, set as a DHCP reservation in Unifi —
  # distinct from defiant's own reservation (192.168.20.10, staying with
  # defiant until the Phase 2 cutover). Not yet consumed by any custom.*
  # option — this host has no DNS or other service module enabled in this
  # Phase 1 PR; wire it into custom.dns.lanIp (or equivalent) when Phase 2
  # brings the homelab stack over.
  networking.hostName = "reliant";

  # Per-host override of the shared default (10, profiles/common/base.nix) —
  # the 120GB mSATA disk has far less headroom than enterprise-d/excelsior's
  # NVMe/SSDs, and defiant's SD card already showed what an unbounded (or
  # too-high) generation count does to a small, fixed disk (see
  # hosts/defiant/README.md § Known Gotchas). Kept in sync with
  # hardware.nix's boot.loader.systemd-boot.configurationLimit (also 5).
  # Revisit both once real disk usage after Phase 2 is known.
  custom.nix.gc.keepGenerations = 5;

  system.stateVersion = "25.11";
}
