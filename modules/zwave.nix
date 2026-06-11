{
  config,
  lib,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.custom.zwave;
in {
  options.custom.zwave = {
    enable = mkEnableOption "Z-Wave JS";

    serialPort = mkOption {
      type = types.str;
      default = "/dev/ttyACM0";
      description = "Serial port for the Z-Wave USB dongle.";
    };
  };

  config = mkIf cfg.enable {
    services.zwave-js = {
      enable = true;
      inherit (cfg) serialPort;
    };

    users.users.zwave-js.extraGroups = ["dialout"];
  };
}
