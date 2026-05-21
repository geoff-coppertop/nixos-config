{pkgs, ...}: {
  programs.firefox.enable = true;

  home.packages = with pkgs; [
    mediawriter
    bitwarden-desktop
    google-chrome
    moonlight-qt
    signal-desktop
  ];
}
