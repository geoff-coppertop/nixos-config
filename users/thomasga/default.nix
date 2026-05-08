{ pkgs, ... }:

{
  imports = [
    ../common/base.nix
    ../common/gui-apps.nix
    ./git.nix
    ./gnome.nix
    ./vscode.nix
    ./secrets.nix
    ./shells.nix
  ];

  home.packages = [
    pkgs.vim
    pkgs.neofetch
    pkgs.nerd-fonts.droid-sans-mono
  ];
}
