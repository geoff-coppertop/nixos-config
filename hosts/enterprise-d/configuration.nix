{...}: {
  imports = [
    ./hardware.nix
    ./power.nix
    ./disko.nix

    ../../roles

    ../../modules
  ];

  custom = {
    backups = {
      enable = true;

      nas = {
        credentialsFile = "/run/agenix/thomasga/nas-smb-credentials";
        host = "192.168.1.231";
        share = "Personal-Drive/backups";
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

  system.stateVersion = "25.11";
}
