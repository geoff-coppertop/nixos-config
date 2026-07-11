{
  config,
  lib,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.custom.syncthingClient;
in {
  options.custom.syncthingClient = {
    enable = mkEnableOption "Syncthing client (syncs this user's Obsidian vault)";

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

  config = mkIf cfg.enable {
    # No declarative settings.folders/devices here: home-manager's
    # services.syncthing generates a syncthing-init unit to merge any
    # declared settings.* into the running config, and on this nixpkgs
    # pin that unit hardcodes ~/.local/state/syncthing/config.xml —  a
    # path syncthing 2.0.15 (started with no --config/--data override)
    # never actually writes to, so the merge loops forever waiting for a
    # file that will never exist there. Reproduced live: hung for 7+
    # hours, blocked a nixos-rebuild switch outright. Configure the
    # obsidian-vault folder and any device pairing by hand via the
    # Syncthing GUI (http://127.0.0.1:8384) instead, until that mismatch
    # is fixed upstream.
    services.syncthing = {
      enable = true;

      # Inject stable identity when secrets are available; auto-generate on first boot
      cert = cfg.certFile;
      key = cfg.keyFile;
    };
  };
}
