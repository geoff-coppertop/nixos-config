{
  config,
  lib,
  ...
}: let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.custom.syncthingHub;
in {
  options.custom.syncthingHub = {
    enable = mkEnableOption "always-on Syncthing hub for per-user folder sync (e.g. Obsidian vaults)";
  };

  config = mkIf cfg.enable {
    # Deliberately enable-only. Devices, folders, and GUI credentials are
    # managed through the Syncthing web GUI, not settings.*, because the
    # NixOS module's syncthing-init applies each declared settings section
    # with PUT — replacing the whole section — so a partially-declared
    # section silently wipes GUI-set state (pairings, folder shares, the
    # GUI password) on every rebuild. GUI-managed state lives in
    # /var/lib/syncthing/.config/syncthing/ and survives rebuilds.
    #
    # Per-user convention: one folder per user per vault, accepted on the
    # hub at /var/lib/syncthing/<user>/<folder>. Users never log into the
    # hub; all hub files are owned by the syncthing user. See README
    # § Obsidian Vault Sync (Syncthing).
    #
    # The GUI stays on the loopback default (127.0.0.1:8384); reach it via
    # an SSH tunnel. It is not exposed through Traefik: the GUI is
    # unauthenticated until a password is set, and a declarative password
    # would land in the world-readable Nix store.
    services.syncthing = {
      enable = true;
      # 22000/tcp+udp (sync) and 21027/udp (local discovery)
      openDefaultPorts = true;
    };
  };
}
