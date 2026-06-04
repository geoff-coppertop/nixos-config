{pkgs, ...}: {
  home.packages = with pkgs; [
    bat
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
