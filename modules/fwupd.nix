{
  config,
  lib,
  ...
}: let
  inherit (lib) mkEnableOption mkIf;
in {
  options.custom.fwupd.enable = mkEnableOption "firmware updates via fwupd/LVFS";

  config = mkIf config.custom.fwupd.enable {
    services.fwupd.enable = true;
  };
}
