{
  config,
  lib,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.custom.zwave;
  defaultSecretsConfigFile = "/var/lib/zwave-js/secrets.json";
in {
  options.custom.zwave = {
    enable = mkEnableOption "Z-Wave JS";

    serialPort = mkOption {
      type = types.str;
      default = "/dev/ttyACM0";
      description = "Serial port for the Z-Wave USB dongle.";
    };

    port = mkOption {
      type = types.port;
      default = 3000;
      description = ''
        Port for the zwave-js WebSocket server (services.zwave-js.port
        upstream default). Confirmed live: AdGuardHome's own admin UI
        already claims 3000 on defiant, so zwave-js deterministically
        crash-looped on EADDRINUSE every restart, ~15s in (once its
        driver finished initializing and tried to bind) — override this
        per-host to whatever's actually free.
      '';
    };

    secretsConfigFile = mkOption {
      type = types.str;
      default = defaultSecretsConfigFile;
      description = ''
        Path to a JSON file providing securityKeys (S0_Legacy,
        S2_Unauthenticated, S2_Authenticated, S2_AccessControl — each a
        32-hex-char/16-byte string). Upstream services.zwave-js.secretsConfigFile
        has no default and must always be set. Confirmed live: contrary
        to this option's original assumption, zwave-js-server does NOT
        generate these itself on first run — it hard-fails
        ("securityKeys.S0_Legacy key is missing") and crash-loops forever
        against an empty/placeholder file. Override to an agenix-managed
        path providing real generated keys; the default only exists so
        the service has somewhere non-empty to point at before that's
        set up.
      '';
    };
  };

  config = mkIf cfg.enable {
    services.zwave-js = {
      enable = true;
      inherit (cfg) serialPort secretsConfigFile port;
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
    # placeholder so the service has something to load before the real
    # agenix-managed secretsConfigFile is wired up.
    #
    # Only applies to the module's own default path: once secretsConfigFile
    # is overridden to an agenix path (/run/agenix/...), agenix's own
    # activation script owns and populates that entire directory tree —
    # the "d" tmpfiles type re-enforces ownership/mode on every activation,
    # even on an already-existing directory, which would fight agenix over
    # permissions on /run/agenix/defiant (shared by every other secret for
    # this host) rather than just seeding a harmless placeholder.
    systemd.tmpfiles.rules = mkIf (cfg.secretsConfigFile == defaultSecretsConfigFile) [
      "d ${dirOf cfg.secretsConfigFile} 0750 zwave-js zwave-js -"
      "f ${cfg.secretsConfigFile} 0600 zwave-js zwave-js - {}"
    ];
  };
}
