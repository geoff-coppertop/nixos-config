{
  # config.fish is dotfiles-owned (geoff-coppertop/dotfiles) and already
  # sources the fzf widget/key-bindings directly, so home-manager must not
  # also inject them.
  programs.fzf = {
    enable = true;

    enableFishIntegration = false;

    defaultCommand = "fd --type f";

    fileWidgetCommand = "fd --type f";

    changeDirWidgetCommand = "fd --type d";
  };
}
