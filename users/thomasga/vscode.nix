{ config, pkgs, ... }:

let
  shellProfiles = {
    fish = {
      path = "${pkgs.fish}/bin/fish";
    };
    zsh = {
      path = "${pkgs.zsh}/bin/zsh";
    };
  };
in
{
  programs.vscode.enable = true;
  programs.vscode.package = pkgs.vscode;
  programs.vscode.userSettings = {
    "files.autoSave" = "onFocusChange";
    "terminal.integrated.defaultProfile.linux" = config.custom.cli.shell;
    "terminal.integrated.profiles.linux" = shellProfiles;
  };

  programs.vscode.extensions = with pkgs.vscode-extensions; [
    ms-python.python
    ms-vscode.cpptools
  ];
}
