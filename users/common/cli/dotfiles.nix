{dotfiles, ...}: {
  home.file = {
    ".config/fish/config.fish".source = "${dotfiles}/fish/config.fish";
    ".config/git/config".source = "${dotfiles}/git/config";
    ".config/git/commit-template".source = "${dotfiles}/git/commit-template";
  };
}
