# Factorio dedicated (headless) game server.
#
# Unlike modules/dcs-server.nix — which has to run an OCI image because DCS is
# a Windows program under Wine — Factorio ships a single well-behaved Linux
# binary and nixpkgs already has a first-class `services.factorio` module.
# This module is only an `enable` gate; every actual setting (openFirewall,
# game-name, description, ...) is set directly via `services.factorio.*` on
# the host that needs it, not mirrored into a parallel custom.* option.
{
  config,
  lib,
  ...
}: let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.custom.factorioServer;
in {
  options.custom.factorioServer.enable = mkEnableOption "Factorio headless dedicated server (nixpkgs services.factorio)";

  config = mkIf cfg.enable {
    services.factorio.enable = true;
  };
}
