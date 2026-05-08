{ pkgs, ... }:

{
  programs.vscode.enable = true;
  programs.vscode.package = pkgs.vscode;
  programs.vscode.userSettings = {
    "files.autoSave" = "onFocusChange";
  };

  programs.vscode.extensions = with pkgs.vscode-extensions; [
    ms-python.python
    ms-vscode.cpptools
  ];
}
