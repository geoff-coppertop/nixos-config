{pkgs, ...}: {
  imports = [
    ../common/base.nix
    ../common/cli
    ./ai.nix
    ./git.nix
    ./github.nix
    ./ssh.nix
    ./ssh-key.nix
    ./vscode.nix
    ./shell.nix
    ./secrets.nix
  ];

  custom.ai.claude.enable = true;

  home.packages = [
    pkgs.vim
    pkgs.nerd-fonts.droid-sans-mono
  ];
}
