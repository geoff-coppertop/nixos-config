{
  config,
  lib,
  pkgs,
  ...
}: let
  shellProfiles = {
    fish = {
      path = "${pkgs.fish}/bin/fish";
    };
    bash = {
      path = "${pkgs.bash}/bin/bash";
    };
    sh = {
      path = "${pkgs.bash}/bin/sh";
    };
  };
in {
  # home-manager's checkLinkTargets aborts the switch if ~/.vscode/extensions
  # already exists as a real directory (which it does after any manual install),
  # so the mutableExtensionsDir = false symlink never gets placed. Remove the
  # unmanaged directory before that check runs so Nix can own the path.
  home.activation.vscodeExtensionsHandoff = lib.hm.dag.entryBefore ["checkLinkTargets"] ''
    ext="$HOME/.vscode/extensions"
    if [ -d "$ext" ] && [ ! -L "$ext" ]; then
      $DRY_RUN_CMD rm -rf "$ext"
    fi
  '';

  programs.vscode = {
    enable = true;
    package = pkgs.vscode;
    mutableExtensionsDir = false;
    profiles.default = {
      extensions = with pkgs.vscode-extensions; [
        dracula-theme.theme-dracula
        github.vscode-github-actions
        github.vscode-pull-request-github
        gruntfuggly.todo-tree
        mhutchie.git-graph
        ms-azuretools.vscode-containers
        ms-python.python
        ms-vscode.cmake-tools
        ms-vscode.cpptools
        ms-vscode.cpptools-extension-pack
        ms-vscode-remote.remote-containers
      ];
      userSettings = {
        "workbench.colorTheme" = "Dracula";
        "files.autoSave" = "onFocusChange";
        "git.blame.editorDecoration.enabled" = true;
        "terminal.integrated.defaultProfile.linux" = config.custom.cli.shell;
        "terminal.integrated.profiles.linux" = shellProfiles;
        "git.autofetch" = true;
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
}
