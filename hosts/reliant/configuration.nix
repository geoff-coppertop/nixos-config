# Phase 2 — bringing reliant's homelab stack online, migrated from defiant:
# custom.dns, custom.traefik (homelab-network), and custom.home-assistant,
# custom.mqtt, custom.matter, custom.zigbee, custom.zwave, custom.adsb
# (smart-home). Combined into a single PR since both halves target this same
# new host as one coordinated migration — see docs/provisioning.md § Two
# Phases. defiant keeps running every one of these services untouched; this
# is not a cutover. reliant is ready to activate its own instances the
# moment the Zigbee/Z-Wave USB radios are physically relocated to it.
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
    ./home-assistant

    ../../profiles/common
    # NOT: profiles/desktop — no display server
    # NOT: profiles/dev — no devcontainer tooling; the appliance service set
    # brought over in Phase 2 (Home Assistant, Zigbee2MQTT, Z-Wave JS, etc.)
    # doesn't need it — revisit if a future addition does.

    ../../modules
  ];

  # ── Homelab services ──────────────────────────────────────────────────────
  services = {
    # Pass-through USB serial devices for Z-Wave and Zigbee dongles — carried
    # over verbatim from hosts/defiant/configuration.nix ahead of the radios'
    # physical move. Same vendor IDs, same dialout-group target;
    # thomasga is added to "dialout" below to match.
    udev.extraRules = ''
      SUBSYSTEM=="tty", ATTRS{idVendor}=="0658", MODE="0660", GROUP="dialout"
      SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", MODE="0660", GROUP="dialout"
    '';
  };

  custom = {
    users.thomasga =
      thomasga
      // {
        groups = ["wheel" "dialout"];
        avatar = null;
      };

    home-assistant = {
      enable = true;
      # Mirrors hosts/defiant/configuration.nix's extraComponents exactly —
      # see hosts/defiant/README.md § Known Gotchas and
      # docs/smart-home.md § Choosing extraComponents for why each of these
      # is here (mqtt and zwave_js in particular caused real outages on
      # defiant when missing).
      extraComponents = [
        "homekit_controller"
        "matter"
        "ssdp"
        "zwave_js"
        "mqtt"
        "conversation"
        "tts"
        "google_translate"
        "met"
        "camera"
        "image_processing"
        "assist_pipeline"
        "ai_task"
        "assist_satellite"
        "ffmpeg"
      ];
    };

    mqtt.enable = true;

    matter.enable = true;

    zigbee = {
      enable = true;
      # Same physical coordinator as defiant, once moved — confirm with
      # `ls /dev/tty{ACM,USB}*` on this host after the radio is plugged in.
      serialPort = "/dev/ttyUSB0";
      # Same network key content as defiant's — the physical Zigbee
      # coordinator carries its own network state in its NVRAM, so reusing
      # the identical key (rather than generating a new one) is what lets
      # already-paired Zigbee devices keep working without a re-pair. See
      # the PR description for the secrets-warden action this depends on
      # (adding reliant as a recipient of the existing
      # secrets/zigbee/network-key.age, not creating a new one).
      networkKeyFile = "/run/agenix/zigbee/network-key";
    };

    zwave = {
      enable = true;
      # Confirm after the controller is physically moved and plugged in:
      # ls /dev/tty{ACM,USB}*
      serialPort = "/dev/ttyACM0";
      # Same as the Zigbee key above: matched to the physical controller's
      # own NVM state, not the host, so reusing defiant's existing keys
      # (rather than generating new ones) avoids forcing an unnecessary
      # re-pair of every Z-Wave device once the controller moves.
      secretsConfigFile = "/run/agenix/zwave/secrets";
      # 3000 (the module default) collides with AdGuard Home's admin UI,
      # enabled above — same collision documented for defiant in
      # hosts/defiant/README.md § Known Gotchas.
      port = 3001;
    };

    adsb = {
      enable = true;
      # Same physical home-address coordinates as defiant's — location data
      # isn't host- or radio-specific, so this reuses the same secret
      # content (reliant added as a recipient), not a freshly generated one.
      locationEnvFile = "/run/agenix/location/coordinates";
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

      # Three more backup jobs for the appliance state migrated above,
      # reusing defiant's existing job-keyed restic-password secrets (same
      # reasoning as the thomasga job's nas-smb-credentials/restic-password
      # below — job-keyed, not machine-keyed, and the repo path already
      # includes the hostname). hass/zigbee2mqtt paths confirmed live on
      # this host's first boot.
      users = {
        thomasga.enable = true;
        hass = {
          enable = true;
          paths = ["/var/lib/hass"];
          excludePatterns = ["/var/lib/hass/.storage/lovelace*" "/var/lib/hass/home-assistant_v2.db"];
        };
        zigbee2mqtt = {
          enable = true;
          paths = ["/var/lib/zigbee2mqtt"];
          excludePatterns = [];
        };
        # NOT /var/lib/zwave-js — that path never gets created. modules/zwave.nix
        # only seeds /var/lib/zwave-js via a tmpfiles rule when secretsConfigFile
        # is still the module's own default placeholder; both defiant and reliant
        # override it to an agenix path, so that rule never fires and the
        # directory has never existed on either host. zwave-js-server's real
        # network cache (device values/metadata, keyed by home ID) lives at
        # /var/cache/zwave-js instead, via systemd's CacheDirectory= — confirmed
        # live on reliant's first boot (a real ID-prefixed .jsonl/.metadata.jsonl/
        # .values.jsonl set, not an empty directory). /var/cache/zwave-js is
        # itself a symlink to private/zwave-js, same shape as defiant's
        # /var/lib/AdGuardHome symlink gotcha (hosts/defiant/README.md § Known
        # Gotchas) — restic follows a symlink passed as an explicit top-level
        # path, so this works the same way that one does. defiant's own
        # zwave-js backup job has the same /var/lib/zwave-js bug and has likely
        # been silently backing up nothing this whole time; out of scope to fix
        # here since this PR doesn't touch defiant's config.
        zwave-js = {
          enable = true;
          paths = ["/var/cache/zwave-js"];
          excludePatterns = [];
        };
        # Reuses defiant's existing job-keyed restic-password secret, same
        # pattern as the three above. Capitalized — matches defiant's
        # confirmed-live path: /var/lib/AdGuardHome is a symlink to
        # private/AdGuardHome; the lowercase path doesn't exist at all
        # (case-sensitive filesystem).
        adguardhome = {
          enable = true;
          paths = ["/var/lib/AdGuardHome"];
          excludePatterns = [];
        };
      };
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
      # Matches defiant's full subdomain list: home-assistant, adsb, and
      # zigbee (Zigbee2MQTT) all self-register their own Traefik routes when
      # their custom.* modules are enabled (see modules/home-assistant.nix,
      # modules/adsb.nix, modules/zigbee.nix), which they now are, above.
      # dns1 is this host's own AdGuard admin UI; dns2 is the cross-host
      # router to excelsior's, defined by hand below.
      subdomains = ["home" "dns1" "dns2" "adsb" "zigbee"];
      # Renamed from the module default "dns", carried from defiant — dns1
      # (this host) and dns2 (excelsior) pair the two AdGuard instances.
      adminSubdomain = "dns1";
    };

    traefik = {
      enable = true;
      acme = {
        email = "geoff.coppertop@gmail.com";
        dnsProvider = "cloudflare";
        # Reused from defiant's existing secret — just an API credential,
        # not tied to either host's identity, so no reason to mint a
        # second one. See hosts/reliant/secrets.nix.
        environmentFile = "/run/agenix/traefik/cloudflare-api-token";
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
  # defiant until the final cutover). Consumed by custom.dns.lanIp above
  # (via the `lanIp` let-binding) now that Phase 2 has wired the homelab
  # stack over.
  networking.hostName = "reliant";

  # Confirmed live: this host's own custom.backups.nas mount fails without
  # it ("mount error: could not resolve address for unas-pro: Unknown
  # error") — the NAS hostname isn't mDNS-resolvable here, it's a static
  # /etc/hosts alias every host with a NAS mount needs, matching
  # hosts/defiant/configuration.nix and hosts/enterprise-d/configuration.nix.
  networking.hosts.${nas.ip} = [nas.host];

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
