{ pkgs, ... }:

{
  home.packages = with pkgs; [
    bat
    bottom
    btop
    dust
    dua
    duf
    eza
    fd
    jq
    procs
    ripgrep
    tldr
    tree
    unzip
    zip
  ];
}
