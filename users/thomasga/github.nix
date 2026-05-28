{lib, ...}: {
  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true;
  };

  home.activation.writeGhCredentials = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ -f "/run/agenix/thomasga/github-token" ]; then
      $DRY_RUN_CMD mkdir -p "$HOME/.config/gh"
      if [ -z "$DRY_RUN_CMD" ]; then
        token=$(cat "/run/agenix/thomasga/github-token")
        printf 'github.com:\n    oauth_token: %s\n    git_protocol: https\n    user: geoff-coppertop\n' "$token" > "$HOME/.config/gh/hosts.yml"
        chmod 600 "$HOME/.config/gh/hosts.yml"
      fi
    fi
  '';
}
