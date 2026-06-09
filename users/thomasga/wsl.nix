{pkgs, ...}: {
  imports = [
    ../common/base.nix
    ../common/cli
    ./git.nix
    ./ssh.nix
    ./vscode.nix
    ./shell.nix
    ./secrets.nix
  ];

  home.packages = [
    pkgs.vim
    pkgs.nerd-fonts.droid-sans-mono
  ];
}
