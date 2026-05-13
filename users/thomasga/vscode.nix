{
  config,
  pkgs,
  ...
}: let
  shellProfiles = {
    fish = {
      path = "${pkgs.fish}/bin/fish";
    };
    zsh = {
      path = "${pkgs.zsh}/bin/zsh";
    };
  };
in {
  programs = {
    vscode = {
      enable = true;
      package = pkgs.vscode;
      # Wrap existing settings into the default profile
      profiles.default = {
        extensions = with pkgs.vscode-extensions; [
          github.vscode-github-actions
          gruntfuggly.todo-tree
          mhutchie.git-graph
          ms-azuretools.vscode-containers
          ms-python.python
          ms-vscode.cmake-tools
          ms-vscode.cpp-devtools
          ms-vscode.cpptools
          ms-vscode.cpptools-extension-pack
          ms-vscode.cpptools-themes
          ms-vscode-remote.remote-containers
        ];
        userSettings = {
          "files.autoSave" = "onFocusChange";
          "git.blame.editorDecoration.enabled" = true;
          "terminal.integrated.defaultProfile.linux" = config.custom.cli.shell;
          "terminal.integrated.profiles.linux" = shellProfiles;
          "todo-tree.general.tags" = [
            "BUG"
            "HACK"
            "FIXME"
            "TODO"
            "XXX"
            "[ ]"
            "[x]"
            "//!! GT:"
          ];
        };
      };
    };
  };
}
