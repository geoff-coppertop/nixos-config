{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.custom.ai.claude;
  rtk = pkgs.callPackage ../../pkgs/rtk.nix {};
in {
  options.custom.ai.claude.rtk.enable = lib.mkOption {
    type = lib.types.bool;
    default = cfg.enable;
    description = ''
      Install RTK (Rust Token Killer) and register its Claude Code auto-rewrite
      hook. RTK transparently rewrites Bash tool calls (e.g. `git status` ->
      `rtk git status`), filtering and compressing their output before it
      reaches the model — 60-90% fewer tokens on noisy dev commands. Defaults on
      wherever Claude AI tools are enabled.
    '';
  };

  config = lib.mkIf (cfg.enable && cfg.rtk.enable) {
    home.packages = [rtk];

    # Claude Code owns ~/.claude/settings.json and writes to it at runtime
    # (permissions, onboarding state, etc.), so it can't be a read-only
    # home.file symlink. Instead merge the RTK PreToolUse hook into the live
    # file on every activation: drop any stale RTK entry and add the current
    # store path, leaving every other key Claude Code has written untouched.
    home.activation.rtkClaudeHook = lib.hm.dag.entryAfter ["writeBoundary"] ''
      CLAUDE_DIR="$HOME/.claude"
      SETTINGS="$CLAUDE_DIR/settings.json"
      HOOK_CMD="${rtk}/bin/rtk hook claude"

      if [ -n "$DRY_RUN_CMD" ]; then
        echo "would ensure RTK PreToolUse hook in $SETTINGS"
      else
        mkdir -p "$CLAUDE_DIR"
        [ -e "$SETTINGS" ] || echo '{}' > "$SETTINGS"
        tmp="$(mktemp)"
        if ${pkgs.jq}/bin/jq --arg cmd "$HOOK_CMD" '
              (.hooks.PreToolUse // []) as $existing
              | .hooks.PreToolUse = ([ $existing[]
                  | select(
                      [ (.hooks // [])[]? | .command // empty ]
                      | any(test("rtk hook claude|rtk-rewrite"))
                      | not
                    ) ]
                  + [ { matcher: "Bash",
                        hooks: [ { type: "command", command: $cmd } ] } ])
            ' "$SETTINGS" > "$tmp"; then
          cmp -s "$tmp" "$SETTINGS" || cat "$tmp" > "$SETTINGS"
          rm -f "$tmp"
        else
          rm -f "$tmp"
          echo "rtk: could not patch $SETTINGS (invalid JSON?); left unchanged" >&2
        fi
      fi
    '';
  };
}
