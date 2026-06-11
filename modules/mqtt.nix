{
  lib,
  config,
  ...
}: let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.custom.mqtt;
in {
  options.custom.mqtt = {
    enable = mkEnableOption "Mosquitto MQTT broker (localhost-only)";
  };

  config = mkIf cfg.enable {
    services.mosquitto = {
      enable = true;
      listeners = [
        {
          address = "127.0.0.1";
          port = 1883;
          settings.allow_anonymous = true;
        }
      ];
    };
  };
}
