{modulesPath, ...}: let
  nas = import ../../lib/nas.nix;
  thomasga = import ../../users/thomasga/account.nix;
  # Defiant's reserved LAN IP — set via Unifi DHCP reservation; fill in after Phase 1
  lanIp = "192.168.1.X";
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
  };

  # ── Hardware ──────────────────────────────────────────────────────────────
  hardware.enableRedistributableFirmware = true;

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
      subdomains = ["homeassistant" "syncthing" "dns" "adsb" "zigbee"];
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
      # Keys generated on first boot — extract from /var/lib/zwave-js/ and encrypt after Phase 1
      secretsConfigFile = "/run/agenix/defiant/zwave-secrets";
    };

    adsb.enable = true;

    syncthing = {
      enable = true;
      hub = true;
      # After Phase 2 of provisioning, uncomment to inject stable identity:
      # certFile = "/run/agenix/defiant/syncthing-cert";
      # keyFile = "/run/agenix/defiant/syncthing-key";
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
          passwordFile = "/run/agenix/defiant/restic-password";
        };
        syncthing = {
          enable = true;
          paths = ["/var/lib/syncthing"];
          excludePatterns = [];
          passwordFile = "/run/agenix/defiant/restic-password";
        };
      };
    };

    isLaptop = false;
  };

  system.stateVersion = "25.11";
}
