{
  imports = [
    ./btrfs.nix
    ./backups.nix
    ./network-drives.nix
    ./snapper.nix
    ./secrets.nix
    ./secure-boot.nix
    ./tpm-luks.nix
    ./framework.nix
    ./framework-control.nix
  ];
}
