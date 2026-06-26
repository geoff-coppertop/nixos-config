{pkgs, ...}: {
  programs.gh.enable = true;

  home.packages = with pkgs; [
    git
    lazygit
    gitui
    delta
  ];
}
