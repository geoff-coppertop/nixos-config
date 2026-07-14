{modulesPath, ...}: let
  nas = import ../../lib/nas.nix;
  thomasga = import ../../users/thomasga/account.nix;
  # Defiant's reserved LAN IP — set via Unifi DHCP reservation; fill in after Phase 1
  lanIp = "192.168.20.10";
in {
  imports = [
    ./secrets.nix
    ./home-assistant
    "${modulesPath}/installer/sd-card/sd-image-aarch64.nix"

    ../../profiles/common
    ../../profiles/dev

    ../../modules
    # NOT: profiles/desktop — no display server
  ];

  # ── Boot ──────────────────────────────────────────────────────────────────
  boot = {
    loader.grub.enable = false;
    loader.generic-extlinux-compatible = {
      enable = true;
      # Unbounded otherwise (module default is 20) — old boot generations
      # accumulate on the SD card's fixed-size partition. Kept in sync with
      # this host's custom.nix.gc.keepGenerations override below (3, down
      # from the shared default of 10) — a full `nix-collect-garbage -d` at
      # the old 10-generation cap still only got the 30G card down to a
      # ~23-24G floor, so both caps dropped together.
      configurationLimit = 3;
    };
    initrd.availableKernelModules = ["xhci_pci" "usbhid" "usb_storage"];
    supportedFilesystems.zfs = false;
  };

  # ── Nix store headroom ────────────────────────────────────────────────────
  # The 30G SD card has no headroom to grow into, unlike the NVMe/SSD hosts.
  # A full `nix-collect-garbage -d` (which also drops all old generations)
  # only got the card down to a ~23-24G floor at the old 10-generation cap —
  # min-free/max-free add proactive GC on top of the weekly nix-gc timer so a
  # build or deploy can trigger collection mid-operation instead of failing
  # outright with "No space left on device". Scoped to this host only —
  # not set in profiles/common/base.nix, since the other hosts have plenty
  # of headroom and shouldn't get the extra GC churn.
  nix.settings = {
    # Below this much free space, a build/copy triggers GC before proceeding.
    min-free = 2 * 1024 * 1024 * 1024; # 2GiB
    # GC (whether triggered by min-free or the weekly timer) deletes store
    # paths down to this much free space, then stops.
    max-free = 5 * 1024 * 1024 * 1024; # 5GiB
  };

  # ── Hardware ──────────────────────────────────────────────────────────────
  hardware.enableRedistributableFirmware = true;

  # Headless — the only way in is SSH with an authorized key
  # (modules/users.nix's authorizedKeysFor), never a physical console.
  # That key check is the actual gate; a sudo password on top of it just
  # blocks unattended remote deploys (nixos-rebuild --target-host) without
  # adding real security.
  security.sudo.wheelNeedsPassword = false;

  # ── Networking ────────────────────────────────────────────────────────────
  networking = {
    hostName = "defiant";
    hosts.${nas.ip} = [nas.host];
  };

  # ── System services ───────────────────────────────────────────────────────
  services = {
    # Pass-through USB serial devices for Z-Wave and Zigbee dongles
    udev.extraRules = ''
      SUBSYSTEM=="tty", ATTRS{idVendor}=="0658", MODE="0660", GROUP="dialout"
      SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", MODE="0660", GROUP="dialout"
    '';

    openssh = {
      enable = true;
      settings = {
        KbdInteractiveAuthentication = false;
        PasswordAuthentication = false;
        PermitRootLogin = "no";
      };
    };
  };

  # ── Homelab services ──────────────────────────────────────────────────────
  custom = {
    # Per-host override of the shared default (10) — see the SD card headroom
    # comment above nix.settings.min-free/max-free.
    nix.gc.keepGenerations = 3;

    users.thomasga =
      thomasga
      // {
        groups = ["wheel" "dialout"];
        avatar = null;
      };

    dns = {
      enable = true;
      domain = "coppertop.ca";
      inherit lanIp;
      # lanSubnet defaults to 192.168.1.0/24 (module default), narrower than
      # the actual network: 3 VLANs, all 192.168.x.0/24. Widened so unbound's
      # access-control covers direct (bypass) queries on port 5335 from any
      # of them, not just defiant's own homelab VLAN (192.168.20.0/24).
      lanSubnet = "192.168.0.0/16";
      # dns1 (this host) and dns2 (excelsior, proxied cross-host below) both
      # terminate TLS at defiant's Traefik, so both resolve locally to
      # defiant's own lanIp.
      subdomains = ["home" "dns1" "dns2" "adsb" "zigbee"];
      # Renamed from the module default "dns" now that a second independent
      # DNS instance (excelsior) exists — dns1/dns2 naming pairs the two.
      adminSubdomain = "dns1";
      # Media services live on excelsior behind its own Traefik; both resolvers
      # must return the same records, so serve excelsior's names here too.
      extraRecords = {
        jellyfin = "192.168.1.10";
        arm = "192.168.1.10";
        tmm = "192.168.1.10";
      };
    };

    traefik = {
      enable = true;
      acme = {
        email = "geoff.coppertop@gmail.com";
        dnsProvider = "cloudflare";
        environmentFile = "/run/agenix/traefik/cloudflare-api-token";
        domain = "coppertop.ca";
      };
    };

    home-assistant = {
      enable = true;
      # zwave_js: confirmed live, "Invalid handler specified" when adding
      # via the UI — doesn't ship in the default_config baseline. mqtt:
      # needed for zigbee2mqtt's bridge discovery messages
      # (zigbee2mqtt/bridge/... topics) to actually create entities, not
      # just publish them unheard — zigbee2mqtt has no HA component of
      # its own. Sonos/LinkPlay (the Sonos+Wiim automation) moved to
      # reliant along with the rest of this appliance layer — see
      # hosts/reliant/configuration.nix and hosts/reliant/README.md.
      #
      # conversation/tts/met/camera/image_processing/assist_pipeline/
      # ai_task/assist_satellite/ffmpeg: confirmed live via the "Invalid
      # config" notification and journalctl — conversation crashed with
      # ModuleNotFoundError: No module named 'hassil' (confirmed via
      # nixpkgs' component-packages.nix: conversation needs hassil +
      # home-assistant-intents, neither bundled since conversation wasn't
      # listed here), and default_config's setup appears to abort
      # partway through on that crash, taking the rest of this list down
      # with it — met, for instance, previously worked fine on its own.
      #
      # google_translate: confirmed live, a separate "Failed to set up"
      # error for its own config entry — it's a distinct TTS platform
      # integration (nixpkgs' component-packages.nix maps it to the gtts
      # package), not covered by adding the core "tts" component above.
      #
      # ssdp: confirmed live via the "Invalid config" notification — one of
      # default_config's own always-loaded discovery integrations (alongside
      # zeroconf), but its deps (nixpkgs' component-packages.nix: async-upnp-
      # client, ifaddr) aren't part of the small default_config baseline
      # either, same gap as the rest of this list.
      extraComponents = [
        # homekit_controller: lets HA drive HomeKit accessories (the outside
        # light switches are HomeKit devices, exposed as switch.* entities).
        # Pairing each accessory's 8-digit code is a one-time UI step;
        # listing the component here just installs its backend.
        "homekit_controller"
        # matter: talks to the python-matter-server enabled by custom.matter
        # below (ws://localhost:5580/ws). Backs the Aqara U100 locks bridged
        # through the Aqara M2 hub, and the future office FP1e presence sensor.
        # Adding the integration and commissioning the hub's pairing code are
        # one-time UI steps; this just installs the component's backend.
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
      # Serial port confirmed after first boot: ls /dev/tty{ACM,USB}*
      serialPort = "/dev/ttyUSB0";
      networkKeyFile = "/run/agenix/zigbee/network-key";
    };

    zwave = {
      enable = true;
      # Serial port confirmed after first boot: ls /dev/tty{ACM,USB}*
      serialPort = "/dev/ttyACM0";
      # Confirmed live: zwave-js-server does not generate securityKeys
      # itself — the module default left this at an empty placeholder
      # since Phase 1, crash-looping (439 restarts) the whole time.
      # Generated real random keys instead of extracting nonexistent ones.
      secretsConfigFile = "/run/agenix/zwave/secrets";
      # 3000 (the module default) is already AdGuardHome's admin UI on
      # this host — confirmed live via `ss -tlnp`/`lsof -i :3000` showing
      # AdGuardHome (not zwave-js) actually holding that port, which is
      # why zwave-js deterministically crash-looped on EADDRINUSE.
      port = 3001;
    };

    adsb = {
      enable = true;
      locationEnvFile = "/run/agenix/location/coordinates";
    };

    backups = {
      enable = true;

      nas = {
        credentialsFile = "/run/agenix/defiant/nas-smb-credentials";
        inherit (nas) host;
        share = nas.shares.backups;
      };

      users = {
        hass = {
          enable = true;
          paths = ["/var/lib/hass"];
          excludePatterns = ["/var/lib/hass/.storage/lovelace*" "/var/lib/hass/home-assistant_v2.db"];
        };
        # Paths are the standard NixOS module state directories for each
        # service; not yet verified against real hardware — confirm with
        # `ls` after Phase 1's first boot, same as the serial ports above.
        zigbee2mqtt = {
          enable = true;
          paths = ["/var/lib/zigbee2mqtt"];
          excludePatterns = [];
        };
        zwave-js = {
          enable = true;
          paths = ["/var/lib/zwave-js"];
          excludePatterns = [];
        };
        adguardhome = {
          enable = true;
          # Capitalized — confirmed live: /var/lib/AdGuardHome is a symlink
          # to private/AdGuardHome. The lowercase path doesn't exist at all
          # (case-sensitive filesystem), so the backup skipped it entirely.
          paths = ["/var/lib/AdGuardHome"];
          excludePatterns = [];
        };
      };
    };

    isLaptop = false;
  };

  # dns2: excelsior runs its own independent unbound+AdGuard instance (real
  # DNS redundancy — clients get both IPs from DHCP), but Traefik only runs
  # here on defiant. modules/dns.nix's self-registration only ever points at
  # 127.0.0.1, so excelsior's admin UI needs a route defined manually,
  # cross-host, rather than through that module. Merges fine alongside the
  # module-contributed routes since dynamicConfigOptions is a freeform TOML
  # type (confirmed: dns.nix/home-assistant.nix/zigbee.nix/adsb.nix already
  # each set their own nested keys under .http.routers/.http.services here).
  services.traefik.dynamicConfigOptions.http = {
    routers.dns2 = {
      rule = "Host(`dns2.coppertop.ca`)";
      service = "dns2";
      tls = {};
    };
    services.dns2.loadBalancer.servers = [{url = "http://192.168.1.10:3000";}];
  };

  system.stateVersion = "25.11";
}
