{pkgs, ...}: {
  imports = [
    ../common/base.nix
    ../common/cli
    ../common/gui-apps.nix
    ./git.nix
    ./gnome.nix
    ./ssh.nix
    ./vscode.nix
    ./secrets.nix
    ./shell.nix
  ];

  home.packages = [
    pkgs.vim
    pkgs.nerd-fonts.droid-sans-mono
    pkgs.obsidian
  ];
}
