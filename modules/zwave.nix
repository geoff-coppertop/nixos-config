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

    secretsConfigFile = mkOption {
      type = types.str;
      description = "Path to JSON file containing Z-Wave S2/S0 network keys (agenix-managed). Keys are generated on first boot — extract from /var/lib/zwave-js/ and encrypt as a secret after Phase 1.";
    };
  };

  config = mkIf cfg.enable {
    services.zwave-js = {
      enable = true;
      inherit (cfg) serialPort secretsConfigFile;
    };

    users.users.zwave-js = {
      isSystemUser = true;
      group = "zwave-js";
      extraGroups = ["dialout"];
    };
    users.groups.zwave-js = {};
  };
}
