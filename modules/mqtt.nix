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
          # allow_anonymous only permits connecting — the ACL plugin
          # NixOS's mosquitto module always loads per listener still
          # defaults to deny-all on topics when its acl file is empty
          # (which it is unless this is set). Without it, zigbee2mqtt and
          # HA's MQTT client both connected fine, but zigbee2mqtt's HA
          # discovery messages were silently dropped — not even
          # retained — since nothing granted topic access at all.
          acl = ["topic readwrite #"];
        }
      ];
    };
  };
}
