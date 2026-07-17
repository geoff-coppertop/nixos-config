{modulesPath, ...}: let
  nas = import ../../lib/nas.nix;
  thomasga = import ../../users/thomasga/account.nix;
  # Defiant's reserved LAN IP — set via Unifi DHCP reservation; fill in after Phase 1
  lanIp = "192.168.20.10";
in {
  imports = [
    ./secrets.nix
    ./appletv-av.nix
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
      subdomains = ["homeassistant" "dns" "adsb" "zigbee"];
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

    home-assistant.enable = true;

    mqtt.enable = true;

    zigbee = {
      enable = true;
      # Serial port confirmed after first boot: ls /dev/tty{ACM,USB}*
      serialPort = "/dev/ttyUSB0";
      # networkKeyFile = "/run/agenix/defiant/zigbee-network-key";  # uncomment after Phase 2
    };

    zwave = {
      enable = true;
      # Serial port confirmed after first boot: ls /dev/tty{ACM,USB}*
      serialPort = "/dev/ttyACM0";
      # secretsConfigFile defaults to /var/lib/zwave-js/secrets.json (module
      # default) — zwave-js generates its own keys there on first boot.
      # Extract and encrypt as a secret after Phase 1, then uncomment:
      # secretsConfigFile = "/run/agenix/defiant/zwave-secrets";  # after Phase 2
    };

    adsb.enable = true;

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
