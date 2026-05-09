{ pkgs, ... }:

{
  imports = [
    ./hardware.nix
    ./power.nix
    ./disko.nix

    ../../roles

    ../../modules
  ];

  networking.hostName = "framework";

  custom.isLaptop = true;
  custom.framework.enable = true;

  environment.systemPackages = with pkgs; [
    framework-tool
  ];

  system.stateVersion = "25.11";

  custom.backups = {
    # Enable after adding the NAS host/share and the matching agenix SMB credentials.
    enable = false;

    nas.credentialsFile = "/run/agenix/thomasga/nas-smb-credentials";

    users.thomasga.enable = true;
  };
}
