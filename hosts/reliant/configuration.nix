# Phase 2 (homelab-network) is now under way — custom.dns and custom.traefik
# are enabled below, running in parallel with defiant's own instances (see
# docs/homelab-network.md). smart-home's appliance layer (Home Assistant,
# Zigbee, Z-Wave, Matter, MQTT, ADS-B) is still entirely on defiant and is a
# separate, later PR — see docs/provisioning.md § Two Phases.
_: let
  nas = import ../../lib/nas.nix;
  thomasga = import ../../users/thomasga/account.nix;
  # reliant's own reserved LAN IP (Unifi DHCP reservation) — distinct from
  # defiant's 192.168.20.10, which stays with defiant until the Phase 2
  # cutover step (reassigning that reservation) is done. Do NOT set this to
  # 192.168.20.10 before that cutover — both hosts would otherwise answer
  # split-horizon DNS for the same address while running independently.
  lanIp = "192.168.20.15";
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

    dns = {
      enable = true;
      domain = "coppertop.ca";
      inherit lanIp;
      # Carried from defiant: the module default (192.168.1.0/24) and this
      # host's own VLAN (192.168.20.0/24) each only cover one of the 3 LAN
      # VLANs — widened so unbound's access-control covers direct (bypass)
      # queries on port 5335 from any of them. See
      # docs/homelab-network.md and hosts/defiant/README.md § Known Gotchas.
      lanSubnet = "192.168.0.0/16";
      # Only the subdomains this host's own Traefik instance actually backs
      # right now: its own AdGuard admin UI (dns1) and the cross-host router
      # to excelsior's AdGuard UI (dns2, defined by hand below). defiant's
      # home-assistant/adsb/zigbee subdomains stay off this list until
      # smart-home's own migration PR brings those service modules here —
      # adding them earlier would create A records with nothing behind them
      # on this host.
      subdomains = ["dns1" "dns2"];
      # Renamed from the module default "dns", carried from defiant — dns1
      # (this host) and dns2 (excelsior) pair the two AdGuard instances.
      adminSubdomain = "dns1";
    };

    traefik = {
      enable = true;
      acme = {
        email = "geoff.coppertop@gmail.com";
        dnsProvider = "cloudflare";
        # New host-scoped secret, distinct from defiant/cloudflare-api-token
        # — Cloudflare tokens in this repo are host-scoped, not job-keyed
        # (see docs/secrets.md § Secret Inventory), so reliant gets its own
        # rather than reusing defiant's. Not yet created — see
        # hosts/reliant/secrets.nix.
        environmentFile = "/run/agenix/reliant/cloudflare-api-token";
        domain = "coppertop.ca";
      };
    };
  };

  # dns2: excelsior runs its own independent unbound+AdGuard instance;
  # Traefik only runs on this host (mirroring defiant's setup, carried over
  # so reliant can be the only Traefik instance once defiant retires).
  # modules/dns.nix's self-registration only ever points at 127.0.0.1, so
  # excelsior's admin UI needs a route defined manually, cross-host. Merges
  # fine alongside the module-contributed routes since dynamicConfigOptions
  # is a freeform TOML type. See docs/homelab-network.md § Second DNS
  # Instance (excelsior).
  services.traefik.dynamicConfigOptions.http = {
    routers.dns2 = {
      rule = "Host(`dns2.coppertop.ca`)";
      service = "dns2";
      tls = {};
    };
    services.dns2.loadBalancer.servers = [{url = "http://192.168.1.10:3000";}];
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
  # defiant until the Phase 2 cutover). Consumed by custom.dns.lanIp above
  # (via the `lanIp` let-binding) now that Phase 2 has wired the homelab
  # stack over.
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
