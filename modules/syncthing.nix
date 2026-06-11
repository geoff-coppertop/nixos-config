{
  config,
  lib,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.custom.syncthing;
in {
  options.custom.syncthing = {
    enable = mkEnableOption "Syncthing";

    hub = mkOption {
      type = types.bool;
      default = false;
      description = "Run as a hub (system syncthing user). False = run as thomasga for client use.";
    };

    vaultPath = mkOption {
      type = types.str;
      default =
        if cfg.hub
        then "/var/lib/syncthing/obsidian-vault"
        else "/home/thomasga/Notes";
      description = "Path to the Obsidian vault folder on this machine.";
    };

    certFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Path to the Syncthing TLS certificate (agenix-managed). Null = auto-generate.";
    };

    keyFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Path to the Syncthing TLS key (agenix-managed). Null = auto-generate.";
    };
  };

  config = mkIf cfg.enable (lib.mkMerge [
    {
      services.syncthing = {
        enable = true;
        openFirewall = true;

        user =
          if cfg.hub
          then "syncthing"
          else "thomasga";

        dataDir =
          if cfg.hub
          then "/var/lib/syncthing"
          else "/home/thomasga";

        # Inject stable identity when secrets are available; auto-generate on first boot
        cert = cfg.certFile;
        key = cfg.keyFile;

        # Let devices and folders be managed via the Syncthing UI
        overrideDevices = false;
        overrideFolders = false;

        settings.folders."obsidian-vault" = {
          path = cfg.vaultPath;
          versioning = {
            type = "trashcan";
            params.cleanoutDays = "30";
          };
        };
      };
    }

    # Self-register Traefik route when running as hub (has a web UI)
    (lib.mkIf (cfg.hub && config.custom.traefik.enable) {
      services.traefik.dynamicConfigOptions.http = {
        routers.syncthing = {
          rule = "Host(`syncthing.${config.custom.traefik.acme.domain}`)";
          service = "syncthing";
          tls = {};
        };
        services.syncthing.loadBalancer.servers = [{url = "http://localhost:8384";}];
      };
    })
  ]);
}
