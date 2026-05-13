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
      enable = true;

      nas = {
        credentialsFile = "/run/agenix/thomasga/nas-smb-credentials";
        host = "192.168.1.231"; # or hostname if DNS resolves it
        share = "Personal-Drive/backups"; # share name on the UNAS Pro
      };

      users.thomasga.enable = true;
    };
    framework.enable = true;
    isLaptop = true;
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

  environment.systemPackages = with pkgs; [
    framework-tool
  ];

  networking.hostName = "framework";

  system.stateVersion = "25.11";
}
