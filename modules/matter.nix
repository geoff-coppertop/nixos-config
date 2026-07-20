{
  lib,
  config,
  ...
}: let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.custom.matter;
in {
  options.custom.matter = {
    enable = mkEnableOption "python-matter-server for Home Assistant's Matter integration";
  };

  config = mkIf cfg.enable {
    # python-matter-server: the Matter controller/fabric that Home Assistant's
    # "matter" integration (listed in the host's extraComponents) connects to
    # over WebSocket at ws://localhost:5580/ws. Adding the integration in the
    # UI and commissioning each Matter device with its pairing code — here the
    # Aqara M2 hub, which bridges the U100 locks (and later the office FP1e
    # presence sensor) — are one-time UI steps; enabling the server just
    # installs the backend HA talks to. Runs on the same host as HA (defiant),
    # so HA reaches it over localhost.
    services.matter-server.enable = true;
  };
}
