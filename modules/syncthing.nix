{
  config,
  lib,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.custom.syncthingHub;
in {
  options.custom.syncthingHub = {
    enable = mkEnableOption "Syncthing hub (system syncthing user, always-on)";

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
      networking.firewall = {
        allowedTCPPorts = [22000];
        allowedUDPPorts = [22000 21027];
      };

      # No declarative settings.folders/devices here: home-manager's
      # equivalent services.syncthing module generates a syncthing-init
      # unit to merge any declared settings.* into the running config, and
      # on this nixpkgs pin that unit hardcodes
      # ~/.local/state/syncthing/config.xml — a path syncthing 2.0.15
      # (started with no --config/--data override) never actually writes
      # to, so the merge loops forever waiting for a file that will never
      # exist there. Reproduced live via the client instance (hung for 7+
      # hours, blocked a nixos-rebuild switch outright). Untested here
      # specifically since defiant doesn't exist on real hardware yet, but
      # not worth risking the same failure mode on first deploy — configure
      # the obsidian-vault folder and any device pairing by hand via the
      # Syncthing GUI instead, until that mismatch is fixed upstream.
      services.syncthing = {
        enable = true;
        user = "syncthing";
        dataDir = "/var/lib/syncthing";

        # Inject stable identity when secrets are available; auto-generate on first boot
        cert = cfg.certFile;
        key = cfg.keyFile;
      };
    }

    # Self-register Traefik route (has a web UI)
    (lib.mkIf config.custom.traefik.enable {
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
