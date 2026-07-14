{
  config,
  lib,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkMerge mkOption types;
  mkTraefikRoute = import ../lib/traefik-route.nix;
  cfg = config.custom.jellyfin;
in {
  options.custom.jellyfin = {
    enable = mkEnableOption "Jellyfin media server";

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open Jellyfin's ports in the firewall. Set false when a reverse proxy on this host fronts it.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      services.jellyfin = {
        enable = true;
        openFirewall = cfg.openFirewall;
      };

      # Render nodes for hardware-accelerated transcoding. GPU-specific VAAPI
      # drivers (e.g. intel-media-driver) belong in the host's hardware config.
      hardware.graphics.enable = true;
    }

    # Self-register a Traefik route when this host runs Traefik. Jellyfin has
    # its own accounts, so no auth middleware is added here.
    (mkIf config.custom.traefik.enable {
      services.traefik.dynamicConfigOptions.http = mkTraefikRoute {
        name = "jellyfin";
        port = 8096;
        inherit (config.custom.traefik.acme) domain;
      };
    })
  ]);
}
