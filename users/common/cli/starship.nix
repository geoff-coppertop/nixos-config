{
  # config.fish is dotfiles-owned (geoff-coppertop/dotfiles) and already
  # sources `starship init fish` directly, so home-manager must not also
  # inject it.
  programs.starship = {
    enable = true;
    enableFishIntegration = false;
  };
}
