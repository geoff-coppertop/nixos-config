{
  imports = [
    ./btrfs.nix
    ./backups.nix
    ./snapper.nix
    ./secrets.nix
    ./secure-boot.nix
    ./tpm-luks.nix
    ./framework.nix
  ];
}
