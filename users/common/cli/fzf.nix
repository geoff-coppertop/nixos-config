{
  programs.fzf = {
    enable = true;

    enableFishIntegration = true;
    enableZshIntegration = true;

    defaultCommand = "fd --type f";

    fileWidgetCommand = "fd --type f";

    changeDirWidgetCommand = "fd --type d";
  };
}
