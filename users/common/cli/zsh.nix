{
  config,
  lib,
  ...
}: {
  config = lib.mkIf (config.custom.cli.shell == "zsh") {
    programs.zsh = {
      enable = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
    };
  };
}
