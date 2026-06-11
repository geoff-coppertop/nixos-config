{...}: {
  imports = [
    ./secrets.nix
    ../../roles/common/base.nix
    ../../roles/common/users.nix
    ../../roles/dev

    ../../modules/backups.nix
    ../../modules/secrets.nix
    ../../modules/ssh-known-hosts.nix
    # NOT: secure-boot, tpm-luks, snapper, btrfs — gated; meaningless on WSL
    # NOT: roles/common/networking.nix — Windows manages WSL networking
    # NOT: roles/desktop              — no display server
  ];

  wsl = {
    enable = true;
    defaultUser = "thomasga";
    startMenuLaunchers = true;
  };

  custom.syncthing.enable = true;

  custom.backups = {
    enable = true;

    nas = {
      credentialsFile = "/run/agenix/thomasga/nas-smb-credentials";
      host = "192.168.1.231";
      share = "Personal-Drive/backups";
    };

    users.thomasga.enable = true;
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
