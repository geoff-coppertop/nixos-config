{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.custom.ai.claude.mcpServers.unifi;

  # Packaging tradeoff, deliberately not a pinned nixpkgs derivation:
  #
  # unifi-network-mcp (PyPI) depends on two of its own workspace packages,
  # unifi-core and unifi-mcp-shared, neither of which exists in nixpkgs.
  # Building this the way the rest of this repo prefers -- a pinned
  # `python3Packages.buildPythonApplication` derivation -- would mean
  # packaging three separate PyPI projects by hand (plus re-pinning hashes on
  # every bump) for a beta project that has shipped ~90 releases already.
  # That is a real, recurring maintenance cost for a single personal, local
  # stdio tool, and upstream's own documented install path is `uvx
  # unifi-network-mcp@<version>` (https://github.com/sirkirby/unifi-mcp) --
  # `uv` resolves and caches the wheel and its dependency tree itself.
  #
  # So this wraps `uvx` instead, with the version pinned in-line below (not
  # exposed as an option) so upgrades are still an explicit, reviewable repo
  # change rather than a silent `@latest` float. Revisit as a real nixpkgs
  # derivation if unifi-core/unifi-mcp-shared land in nixpkgs, or if this
  # server graduates out of beta.
  unifiNetworkMcpVersion = "0.25.1";

  wrapper = pkgs.writeShellApplication {
    name = "unifi-network-mcp";
    runtimeInputs = [pkgs.uv];
    text = ''
      # UNIFI_NETWORK_CREDENTIALS_FILE points at a decrypted secret with
      # UNIFI_NETWORK_USERNAME=/UNIFI_NETWORK_PASSWORD= lines; source it so
      # the credentials themselves never appear in the static
      # ~/.claude.json MCP server registration, only this file path does.
      if [ -n "''${UNIFI_NETWORK_CREDENTIALS_FILE:-}" ]; then
        if [ ! -r "$UNIFI_NETWORK_CREDENTIALS_FILE" ]; then
          echo "unifi-network-mcp: credentials file $UNIFI_NETWORK_CREDENTIALS_FILE not readable" >&2
          exit 1
        fi
        set -a
        # shellcheck disable=SC1090
        source "$UNIFI_NETWORK_CREDENTIALS_FILE"
        set +a
      fi
      exec uvx "unifi-network-mcp@${unifiNetworkMcpVersion}" "$@"
    '';
  };
in {
  config = lib.mkIf (config.custom.ai.claude.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.credentialsFile != null;
        message = ''
          custom.ai.claude.mcpServers.unifi.enable is set but
          custom.ai.claude.mcpServers.unifi.credentialsFile is null. Point it
          at the decrypted UniFi controller credentials secret (see
          docs/users.md#unifi-network-mcp-server).
        '';
      }
    ];

    home.packages = [wrapper];

    # Claude Code keeps live session/auth state in ~/.claude.json, so this
    # merges only the `mcpServers.unifi` key in place with jq rather than
    # managing the whole file with home.file, which would clobber that state
    # (and get clobbered back by Claude Code itself) on every switch.
    home.activation.registerUnifiNetworkMcpServer = lib.hm.dag.entryAfter ["writeBoundary"] ''
      if [ -z "$DRY_RUN_CMD" ]; then
        claudeConfig="$HOME/.claude.json"
        server=$(${pkgs.jq}/bin/jq -n \
          --arg command "${wrapper}/bin/unifi-network-mcp" \
          --arg host "${cfg.host}" \
          --arg port "${toString cfg.port}" \
          --arg site "${cfg.site}" \
          --arg verifySsl "${lib.boolToString cfg.verifySsl}" \
          --arg credentialsFile "${toString cfg.credentialsFile}" \
          '{
            type: "stdio",
            command: $command,
            args: [],
            env: {
              UNIFI_NETWORK_HOST: $host,
              UNIFI_NETWORK_PORT: $port,
              UNIFI_NETWORK_SITE: $site,
              UNIFI_NETWORK_VERIFY_SSL: $verifySsl,
              UNIFI_NETWORK_CREDENTIALS_FILE: $credentialsFile
            }
          }')
        if [ -f "$claudeConfig" ]; then
          tmp=$(mktemp)
          ${pkgs.jq}/bin/jq --argjson server "$server" '.mcpServers.unifi = $server' "$claudeConfig" > "$tmp"
          mv "$tmp" "$claudeConfig"
        else
          mkdir -p "$(dirname "$claudeConfig")"
          ${pkgs.jq}/bin/jq -n --argjson server "$server" '{mcpServers: {unifi: $server}}' > "$claudeConfig"
        fi
      fi
    '';
  };
}
