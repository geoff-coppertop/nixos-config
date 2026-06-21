{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf;
in {
  options.custom.vr.enable = mkEnableOption "VR support (ALVR wireless streaming)";

  config = mkIf config.custom.vr.enable {
    environment.systemPackages = with pkgs; [
      alvr
    ];

    networking.firewall = {
      allowedTCPPorts = [9943 9944];
      allowedUDPPorts = [9944];
    };
  };
}
