{...}: let
  nas = import ../../lib/nas.nix;
in {
  imports = [
    ./hardware.nix
    ./power.nix
    ./disko.nix
    ./secrets.nix

    ../../roles

    ../../modules
  ];

  custom = {
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
        host = nas.host;
        share = nas.shares.backups;
      };

      users.thomasga.enable = true;
    };
    btrfs.enable = true;
    framework.enable = true;
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

  services.framework-control.enable = true;

  networking.hostName = "enterprise-d";
  networking.hosts.${nas.ip} = [nas.host];

  system.stateVersion = "25.11";
}
