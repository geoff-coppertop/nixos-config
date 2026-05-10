{pkgs, ...}: {
  imports = [
    ./hardware.nix
    ./power.nix
    ./disko.nix

    ../../roles

    ../../modules
  ];

  custom = {
    backups = {
      # Enable after adding the NAS host/share and the matching agenix SMB credentials.
      enable = false;

      nas.credentialsFile = "/run/agenix/thomasga/nas-smb-credentials";

      users.thomasga.enable = true;
    };
    framework.enable = true;
    isLaptop = true;
  };

  environment.systemPackages = with pkgs; [
    framework-tool
  ];

  networking.hostName = "framework";

  system.stateVersion = "25.11";
}
