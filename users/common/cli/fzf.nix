{
  programs.fzf = {
    enable = true;

    enableFishIntegration = false;

    # Not a nushell user; also keeps the fzf>=0.73 nushell assertion in newer
    # home-manager from tripping while nixpkgs still ships 0.72.
    enableNushellIntegration = false;

    defaultCommand = "fd --type f";

    fileWidget.command = "fd --type f";

    changeDirWidget.command = "fd --type d";
  };
}
