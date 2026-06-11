_: let
  thomasga = import ../../users/thomasga/account.nix;
in {
  imports = [
    ./secrets.nix
    ../../roles/common
    ../../roles/dev

    ../../modules
    # NOT: roles/desktop — no display server
  ];

  wsl = {
    enable = true;
    defaultUser = "thomasga";
    startMenuLaunchers = true;
  };

  custom = {
    users.thomasga =
      thomasga
      // {
        groups = ["wheel" "networkmanager"];
        avatar = null;
      };

    backups = {
      enable = true;

      nas = {
        credentialsFile = "/run/agenix/thomasga/nas-smb-credentials";
        host = "192.168.1.231";
        share = "Personal-Drive/backups";
      };

      users.thomasga.enable = true;
    };
  };

  services.openssh = {
    enable = true;
    settings = {
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  networking.hostName = "holodeck-01";
  system.stateVersion = "25.11";
}
