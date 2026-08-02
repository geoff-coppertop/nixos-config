{
  config,
  lib,
  ...
}: let
  inherit (lib) mkEnableOption mkIf;
in {
  options.custom.gameStreaming.enable = mkEnableOption "Sunshine game-streaming host";

  config = mkIf config.custom.gameStreaming.enable {
    services.sunshine = {
      enable = true;
      capSysAdmin = true;
      openFirewall = true;
      autoStart = true;
    };
  };
}
