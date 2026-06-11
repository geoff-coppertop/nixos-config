{
  config,
  lib,
  pkgs,
  ...
}: {
  options.custom.ai = {
    claude.enable = lib.mkEnableOption "Claude AI tools";
    copilot.enable = lib.mkEnableOption "GitHub Copilot integration";
  };

  config = lib.mkMerge [
    (lib.mkIf config.custom.ai.claude.enable {
      home.packages = [pkgs.claude-code];
    })
    (lib.mkIf (config.custom.ai.claude.enable && config.programs.vscode.enable) {
      programs.vscode.profiles.default.extensions = [
        pkgs.vscode-marketplace.anthropic.claude-code
      ];
    })
    (lib.mkIf (config.custom.ai.copilot.enable && config.programs.vscode.enable) {
      programs.vscode.profiles.default.extensions = [
        pkgs.vscode-marketplace.github.copilot
        pkgs.vscode-marketplace.github.copilot-chat
      ];
    })
    (lib.mkIf (!config.custom.ai.copilot.enable && config.programs.vscode.enable) {
      programs.vscode.profiles.default.userSettings = {
        "chat.disableAIFeatures" = true;
      };
    })
  ];
}
