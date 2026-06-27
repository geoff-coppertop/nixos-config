{
  config,
  pkgs,
  ...
}: {
  home.file.".config/git/ignore".text = ''
    # Global git ignore patterns
  '';

  # Aliases, color, commit.template, fetch/log/merge/pull/rebase/status
  # settings now come from geoff-coppertop/dotfiles, via
  # ~/.config/git/config. That file includes config-local below, which
  # stays home-manager-owned so identity isn't published to a shared repo.
  home.file.".config/git/config-local".text = ''
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
}
