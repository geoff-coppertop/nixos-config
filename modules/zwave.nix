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
      default = "/var/lib/zwave-js/secrets.json";
      description = "Path where Z-Wave S2/S0 network keys are stored. Upstream services.zwave-js.secretsConfigFile has no default and must always be set — it's not a preset-keys file, it's where zwave-js itself writes the keys it generates on first run. The default here points inside the service's own state directory, so it just works out of the box. Override to an agenix-managed path (after extracting the generated keys post-Phase-1) to persist them across reinstalls.";
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

    # systemd's LoadCredential (which secretsConfigFile is passed through as)
    # requires the source file to already exist at unit start — it will not
    # create one. Confirmed live: first boot failed with EXIT_CREDENTIALS
    # (243) because nothing had ever created this file. Pre-seed an empty
    # JSON object so the service's first run has something to load and can
    # then write its generated keys into it.
    systemd.tmpfiles.rules = [
      "d ${dirOf cfg.secretsConfigFile} 0750 zwave-js zwave-js -"
      "f ${cfg.secretsConfigFile} 0600 zwave-js zwave-js - {}"
    ];
  };
}
