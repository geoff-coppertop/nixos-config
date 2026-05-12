{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    moonlight-qt
  ];

  hardware = {
    graphics = {
      enable = true;
      enable32Bit = true;
    };
    steam-hardware.enable = true;
  };

  programs = {
    gamemode.enable = true;

    steam = {
      enable = true;
      remotePlay.openFirewall = true;
      extraCompatPackages = with pkgs; [proton-ge-bin];
    };
  };
}
