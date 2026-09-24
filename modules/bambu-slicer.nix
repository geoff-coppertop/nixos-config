# See docs/workstation.md § Bambu Lab Printer Discovery (SSDP).
{
  config,
  lib,
  ...
}: let
  inherit (lib) mkEnableOption mkIf;
in {
  options.custom.bambuSlicer.enable = mkEnableOption "Bambu Lab printer discovery (SSDP) for OrcaSlicer/Bambu Studio";

  config = mkIf config.custom.bambuSlicer.enable {
    networking.firewall.allowedUDPPorts = [2021];
  };
}
