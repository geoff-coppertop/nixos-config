{pkgs, ...}: let
  nas = import ../../lib/nas.nix;
  thomasga = import ../../users/thomasga/account.nix;
  framework-penguin-plymouth = import ./framework-penguin-plymouth.nix {inherit pkgs;};
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
        # thomasga's home directory is this host's only backup job, and the
        # user's personal backup deliberately stays on their own NAS login
        # against the pre-existing Personal-Drive/backups path (the same
        # restic repository this job has always used — nas.shares.personal
        # is the bare Personal-Drive root, a different remote location, and
        # would silently start an unrelated empty repository) rather than
        # moving to the shared backup-svc account. With no appliance jobs
        # here there is nothing to keep on the Backups share, so the
        # host-wide target is simply the personal one — no per-entry
        # custom.backups.users.<name>.nas override needed (that is what
        # reliant and excelsior use, where the two coexist).
        credentialsFile = "/run/agenix/thomasga/nas-smb-credentials";
        inherit (nas) host;
        share = nas.shares.personalBackups;
        mountPoint = "/mnt/nas-personal-backups";
      };

      users.thomasga.enable = true;
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

  boot = {
    # Lets `nix build` cross-compile aarch64-linux derivations via qemu-user
    # emulation instead of failing with "platform mismatch". Slow — full
    # emulation, not native — but there's no remote aarch64 builder set up.
    # No host currently uses aarch64-linux; kept for a future one.
    binfmt.emulatedSystems = ["aarch64-linux"];

    plymouth = {
      enable = true;
      theme = "framework-penguin";
      themePackages = [framework-penguin-plymouth];
    };
    # Plymouth only gets a clean console to render into if the kernel and
    # systemd are told to keep quiet — without these, boot-time log lines
    # print straight over (and effectively replace) the splash.
    consoleLogLevel = 3;
    initrd.verbose = false;
    kernelParams = [
      "quiet"
      "splash"
      "udev.log_priority=3"
      "rd.systemd.show_status=auto"
    ];
  };

  networking.hostName = "enterprise-d";
  networking.hosts.${nas.ip} = [nas.host];

  system.stateVersion = "25.11";
}
