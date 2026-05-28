{
  config,
  lib,
  pkgs,
  ...
}: {
  options.custom.claude.enable = lib.mkEnableOption "Claude AI tools";

  config = lib.mkIf config.custom.claude.enable {
    home.packages = [pkgs.claude-code];

    programs.vscode.profiles.default.extensions = with pkgs.vscode-marketplace; [
      anthropic.claude-code
    ];
  };
}
