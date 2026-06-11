{
  lib,
  modulesPath,
  ...
}: let
  nas = import ../../lib/nas.nix;
  # Defiant's reserved LAN IP — set via Unifi DHCP reservation; fill in after Phase 1
  lanIp = "192.168.1.X";
in {
  imports = [
    ./secrets.nix
    "${modulesPath}/installer/sd-card/sd-image-aarch64.nix"

    ../../roles/common/base.nix
    ../../roles/common/users.nix
    ../../roles/dev

    ../../modules
    # NOT: roles/desktop — no display server
    # NOT: roles/common/networking.nix — no Wi-Fi profiles needed
    # NOT: secure-boot, tpm-luks, snapper, btrfs — not applicable to RPi4 SD card
    # NOT: framework — laptop-specific hardware
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

  # roles/common/users.nix adds thomasga to networkmanager group; defiant has
  # no NetworkManager so the group doesn't exist — override to prevent activation failure.
  users.users.thomasga.extraGroups = lib.mkForce ["wheel" "dialout"];

  # ── Homelab services ──────────────────────────────────────────────────────
  custom = {
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
        credentialsFile = "/run/agenix/defiant/cloudflare-api-token";
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
