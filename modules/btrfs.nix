{
  config,
  lib,
  ...
}: {
  options.custom.btrfs.enable = lib.mkEnableOption "btrfs compression on root filesystem";
  config = lib.mkIf config.custom.btrfs.enable {
    fileSystems."/".options = ["compress=zstd"];
  };
}
