{
  config,
  lib,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.custom.syncthing;
in {
  options.custom.syncthing = {
    enable = mkEnableOption "per-user Syncthing instance for vault syncing";

    guiPort = mkOption {
      type = types.port;
      default = 8384;
      description = "Loopback port for this user's Syncthing web GUI. Every user running Syncthing on the same machine needs a distinct port.";
    };
  };

  config = mkIf cfg.enable {
    # Enable-only for the same reason as modules/syncthing-hub.nix: the
    # home-manager module's syncthing-init applies declared settings
    # sections with PUT, wiping GUI-set state (device pairings, folder
    # shares) on every rebuild. Pair devices and add folders via the GUI;
    # that state persists in ~/.local/state/syncthing/.
    #
    # No firewall ports are opened on clients: the client dials out to the
    # hub (defiant), which has 22000 open. If two users' instances race for
    # the default 22000 listen port the loser just falls back to outbound
    # dialing, which is all a client needs.
    services.syncthing = {
      enable = true;
      guiAddress = "127.0.0.1:${toString cfg.guiPort}";
    };
  };
}
