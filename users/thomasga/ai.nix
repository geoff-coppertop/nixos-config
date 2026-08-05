{
  config,
  lib,
  pkgs,
  ...
}: {
  options.custom.ai = {
    claude.enable = lib.mkEnableOption "Claude AI tools";

    # Local stdio MCP servers registered with Claude Code (~/.claude.json,
    # user scope). One attribute per server; see users/thomasga/ai-mcp-unifi.nix
    # for the only server currently defined (`unifi`).
    claude.mcpServers.unifi = {
      enable = lib.mkEnableOption "UniFi Network MCP server (stdio, local subprocess only)";

      host = lib.mkOption {
        type = lib.types.str;
        description = "Hostname or IP of the UniFi Network controller.";
        example = "192.168.1.1";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 443;
        description = "UniFi Network controller port.";
      };

      site = lib.mkOption {
        type = lib.types.str;
        default = "default";
        description = "UniFi site name.";
      };

      verifySsl = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Verify the controller's TLS certificate. Defaults to false because
          self-hosted UniFi controllers typically present a self-signed cert.
        '';
      };

      credentialsFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Path to a decrypted, EnvironmentFile-style secret containing
          `UNIFI_NETWORK_USERNAME=` and `UNIFI_NETWORK_PASSWORD=` lines for a
          dedicated local (non-SSO) UniFi admin account. This is a runtime
          path (e.g. under /run/agenix/), never the secret contents
          themselves — set per-host, not here. See
          docs/users.md#unifi-network-mcp-server for the current secret name.
        '';
      };
    };

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
