{
  imports = [
    ./hardware.nix
    ./power.nix
    ./disko.nix

    ../../roles/common/base.nix
    ../../roles/common/networking.nix
    ../../roles/common/users.nix
    ../../roles/common/gaming.nix
    ../../roles/common/flatpak.nix

    ../../roles/desktop
    ../../roles/dev

    ../../modules/btrfs.nix
    ../../modules/backups.nix
    ../../modules/snapper.nix
    ../../modules/secrets.nix
    ../../modules/secure-boot.nix
    ../../modules/tpm-luks.nix
  ];

  networking.hostName = "framework";

  custom.isLaptop = true;

  custom.backups = {
    # Enable after adding the NAS host/share and the matching agenix SMB credentials.
    enable = false;

    nas.credentialsFile = "/run/agenix/thomasga/nas-smb-credentials";

    users.thomasga.enable = true;
  };
}
