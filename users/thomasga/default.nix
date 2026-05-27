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

  # home-manager can't manage empty directories; .keep causes ~/builds to be created
  home.file."builds/.keep".text = "";
}
