{
  # config.fish is dotfiles-owned (geoff-coppertop/dotfiles) and already
  # sources `zoxide init fish` directly, so home-manager must not also
  # inject it.
  programs.zoxide = {
    enable = true;
    enableFishIntegration = false;
  };
}
