{
  config,
  dotfiles,
  pkgs,
  ...
}: {
  home.file = {
    ".config/git/ignore".text = ''
      # Global git ignore patterns
    '';

    # Aliases, color, commit.template, and fetch/log/merge/pull/rebase/status
    # settings come from geoff-coppertop/dotfiles. Note the direction of the
    # dependency: it is the *dotfiles* copy of ~/.config/git/config that carries
    # the `include` of config-local below, so these two files are one mechanism
    # and the include directive lives in that repo, not this one.
    ".config/git/config".source = "${dotfiles}/git/config";
    ".config/git/commit-template".source = "${dotfiles}/git/commit-template";

    # Identity stays home-manager-owned so it isn't published to a shared repo.
    ".config/git/config-local".text = ''
      [user]
          name = Geoffrey Thomas
          email = geoff.coppertop@gmail.com

      [core]
          editor = ${pkgs.vim}/bin/vim
          excludesfile = ${config.home.homeDirectory}/.config/git/ignore

      [safe]
          directory = /etc/nixos/nixos-config

      [credential "https://github.com"]
          helper = !gh auth git-credential

      [credential "https://gist.github.com"]
          helper = !gh auth git-credential
    '';
  };
}
