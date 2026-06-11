{
  config,
  lib,
  pkgs,
  ...
}: {
  options.custom.ai = {
    claude.enable = lib.mkEnableOption "Claude AI tools";
    copilot.enable = lib.mkEnableOption "GitHub Copilot integration";
    obsidian.enable = lib.mkEnableOption "Obsidian MCP server for Claude Code";
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
    (lib.mkIf config.custom.ai.obsidian.enable (let
      mcpObsidian = pkgs.callPackage ../../pkgs/mcp-obsidian.nix {};
      mcpLauncher = pkgs.writeShellApplication {
        name = "mcp-obsidian-launcher";
        runtimeInputs = [mcpObsidian];
        text = ''
          key="/run/agenix/thomasga/obsidian-api-key"
          if [ ! -f "$key" ]; then
            echo "mcp-obsidian: API key not found at $key" >&2
            echo "Create it: nix run .#secret-edit -- secrets/thomasga/obsidian-api-key.age" >&2
            exit 1
          fi
          OBSIDIAN_API_KEY="$(cat "$key")"
          export OBSIDIAN_API_KEY
          exec mcp-obsidian
        '';
      };
    in {
      home.activation.claudeMcpJsonHandoff = lib.hm.dag.entryBefore ["checkLinkTargets"] ''
        f="$HOME/.claude/.mcp.json"
        if [ -f "$f" ] && [ ! -L "$f" ]; then
          $DRY_RUN_CMD rm -f "$f"
        fi
      '';
      home.file.".claude/.mcp.json".text = builtins.toJSON {
        mcpServers.obsidian.command = lib.getExe mcpLauncher;
      };
    }))
  ];
}
