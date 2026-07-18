{modulesPath, ...}: let
  nas = import ../../lib/nas.nix;
  thomasga = import ../../users/thomasga/account.nix;
  # Defiant's reserved LAN IP — set via Unifi DHCP reservation; fill in after Phase 1
  lanIp = "192.168.20.10";
in {
  imports = [
    ./secrets.nix
    "${modulesPath}/installer/sd-card/sd-image-aarch64.nix"

    ../../roles/common
    ../../roles/dev

    ../../modules
    # NOT: roles/desktop — no display server
  ];

  # ── Boot ──────────────────────────────────────────────────────────────────
  boot = {
    loader.grub.enable = false;
    loader.generic-extlinux-compatible.enable = true;
    initrd.availableKernelModules = ["xhci_pci" "usbhid" "usb_storage"];
    supportedFilesystems.zfs = false;
  };

  # ── Hardware ──────────────────────────────────────────────────────────────
  hardware.enableRedistributableFirmware = true;

  # Headless — the only way in is SSH with an authorized key
  # (roles/common/users.nix's authorizedKeysFor), never a physical console.
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
      # lanSubnet defaults to 192.168.1.0/24 (module default), which isn't
      # defiant's actual subnet — it's reserved at 192.168.20.10. Overriding
      # to match, so unbound's access-control actually covers defiant's own
      # LAN for direct (bypass) queries on port 5335.
      lanSubnet = "192.168.20.0/24";
      subdomains = ["home" "dns" "adsb" "zigbee"];
    };

    traefik = {
      enable = true;
      acme = {
        email = "geoff.coppertop@gmail.com";
        dnsProvider = "cloudflare";
        environmentFile = "/run/agenix/defiant/cloudflare-api-token";
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
      # its own. Sonos deferred for now (not in scope yet).
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
      extraComponents = [
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

    zigbee = {
      enable = true;
      # Serial port confirmed after first boot: ls /dev/tty{ACM,USB}*
      serialPort = "/dev/ttyUSB0";
      networkKeyFile = "/run/agenix/defiant/zigbee-network-key";
    };

    zwave = {
      enable = true;
      # Serial port confirmed after first boot: ls /dev/tty{ACM,USB}*
      serialPort = "/dev/ttyACM0";
      # Confirmed live: zwave-js-server does not generate securityKeys
      # itself — the module default left this at an empty placeholder
      # since Phase 1, crash-looping (439 restarts) the whole time.
      # Generated real random keys instead of extracting nonexistent ones.
      secretsConfigFile = "/run/agenix/defiant/zwave-secrets";
      # 3000 (the module default) is already AdGuardHome's admin UI on
      # this host — confirmed live via `ss -tlnp`/`lsof -i :3000` showing
      # AdGuardHome (not zwave-js) actually holding that port, which is
      # why zwave-js deterministically crash-looped on EADDRINUSE.
      port = 3001;
    };

    adsb = {
      enable = true;
      locationEnvFile = "/run/agenix/defiant/location";
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

  system.stateVersion = "25.11";
}
