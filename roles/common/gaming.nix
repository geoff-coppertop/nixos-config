{ pkgs, ... }:

{
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;
  hardware.steam-hardware.enable = true;

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    extraCompatPackages = with pkgs; [ proton-ge-bin ];
  };

  programs.gamemode.enable = true;
}
