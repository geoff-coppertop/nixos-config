{pkgs, ...}: {
  imports = [
    ../common/appearance.nix
    ../common/base.nix
    ../common/cli
    ../common/gui-apps.nix
    ../common/excalidraw.nix
    ./ai.nix
    ./cosmic.nix
    ./easyeffects.nix
    ./git.nix
    ./ghostty.nix
    ./desktop-common.nix
    ./gnome.nix
    ./ssh.nix
    ./ssh-key.nix
    ./vscode.nix
    ./github.nix
    ./secrets.nix
    ./connect-iq.nix
    ./shell.nix
    ./drawio.nix
    ./orca-slicer.nix
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
