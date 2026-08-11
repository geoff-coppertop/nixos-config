_: let
  nas = import ../../lib/nas.nix;
  thomasga = import ../../users/thomasga/account.nix;
in {
  imports = [
    ./hardware.nix
    ./power.nix
    ./disko.nix
    ./secrets.nix

    ../../profiles/common
    ../../profiles/desktop
    ../../profiles/dev

    ../../modules
  ];

  custom = {
    users.thomasga = thomasga // {groups = ["wheel" "networkmanager" "plugdev"];};

    wifi.enable = true;
    gaming.enable = true;
    flatpak.enable = true;
    vr.enable = true;
    debugProbes.enable = true;

    networkDrives = {
      enable = true;
      nas.host = nas.host;
      users.thomasga = {
        enable = true;
        share = nas.shares.personal;
      };
    };

    backups = {
      enable = true;

      nas = {
        credentialsFile = "/run/agenix/thomasga/nas-smb-credentials";
        inherit (nas) host;
        share = nas.shares.backups;
      };

      users.thomasga.enable = true;

      backrest = {
        enable = true;
        listenAddress = "0.0.0.0";
      };
    };
    btrfs.enable = true;
    framework.enable = true;
    fwupd.enable = true;
    isLaptop = true;
    secureBoot.enable = true;
    snapper.enable = true;
    tpmLuks.enable = true;
  };

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # services.framework-control.enable comes from custom.framework.enable above
  # (modules/framework.nix defaults it on for any Framework host); override
  # here only if this host should not run the control service.

  # bitwarden-desktop is still pinned to electron_39 upstream (EOL, no more
  # security patches); nixpkgs marks it insecure. Known, currently-open
  # packaging lag (nixpkgs#529107, nixpkgs#526914) — remove this once
  # bitwarden-desktop is rebuilt against a supported electron release.
  nixpkgs.config.permittedInsecurePackages = ["electron-39.8.10"];

  # Lets `nix build` cross-compile aarch64-linux derivations (e.g. defiant) via
  # qemu-user emulation instead of failing with "platform mismatch". Slow —
  # full emulation, not native — but there's no remote aarch64 builder set up.
  boot.binfmt.emulatedSystems = ["aarch64-linux"];

  networking.hostName = "enterprise-d";
  networking.hosts.${nas.ip} = [nas.host];

  system.stateVersion = "25.11";
}
