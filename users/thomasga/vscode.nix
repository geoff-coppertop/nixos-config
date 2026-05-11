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
          ms-python.python
          ms-vscode.cpptools
        ];
        userSettings = {
          "files.autoSave" = "onFocusChange";
          "terminal.integrated.defaultProfile.linux" = config.custom.cli.shell;
          "terminal.integrated.profiles.linux" = shellProfiles;
        };
      };
    };
  };
}
