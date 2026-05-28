{pkgs, ...}: {
  imports = [
    ../common/base.nix
    ../common/cli
    ../common/gui-apps.nix
    ./claude.nix
    ./git.nix
    ./gnome.nix
    ./ssh.nix
    ./vscode.nix
    ./github.nix
    ./secrets.nix
    ./shell.nix
  ];

  custom.claude.enable = true;

  home.packages = [
    pkgs.vim
    pkgs.nerd-fonts.droid-sans-mono
    pkgs.obsidian
  ];

  # home-manager can't manage empty directories; .keep causes ~/builds to be created
  home.file."builds/.keep".text = "";
}
