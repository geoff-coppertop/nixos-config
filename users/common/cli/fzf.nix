{
  programs.fzf = {
    enable = true;

    defaultCommand = "fd --type f";

    fileWidget.command = "fd --type f";

    changeDirWidget.command = "fd --type d";
  };
}
