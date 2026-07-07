{pkgs, ...}: {
  imports = [
    ../common/appearance.nix
    ../common/base.nix
    ../common/cli
    ../common/gui-apps.nix
    ./ai.nix
    ./git.nix
    ./ghostty.nix
    ./gnome.nix
    ./ssh.nix
    ./ssh-key.nix
    ./vscode.nix
    ./github.nix
    ./secrets.nix
    ./connect-iq.nix
    ./shell.nix
    ./drawio.nix
  ];

  custom.appearance.darkMode = true;
  custom.ai.claude.enable = true;

  home.packages = [
    pkgs.vim
    pkgs.nerd-fonts.droid-sans-mono
    pkgs.obsidian
  ];

  # home-manager can't manage empty directories; .keep causes ~/builds to be created
  home.file."builds/.keep".text = "";
}
