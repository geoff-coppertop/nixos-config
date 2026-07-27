{
  dotfiles,
  pkgs,
  ...
}: {
  custom.cli.shell = "fish";

  # fish_greeting/ls/ll/lt functions and aliases come from
  # geoff-coppertop/dotfiles, shared with devcontainer-features.
  #
  # That file also runs `starship init fish`, `zoxide init fish`, and the fzf
  # key-bindings itself, so home-manager must not inject them a second time.
  # These overrides live here, next to the config.fish that causes them, rather
  # than in users/common/cli/ — a user who lets home-manager manage their shell
  # init wants the upstream default, and shipping the opt-out in a shared module
  # would silently unwire all three tools for them.
  programs = {
    fzf.enableFishIntegration = false;
    starship.enableFishIntegration = false;
    zoxide.enableFishIntegration = false;
  };

  home.file = {
    ".config/fish/config.fish".source = "${dotfiles}/fish/config.fish";

    # The Connect IQ SDK PATH shim is machine-specific dev tooling, so it stays
    # home-manager-owned as a fish conf.d drop-in (sourced regardless of how
    # config.fish is provided) rather than going into the shared dotfiles
    # config.fish.
    ".config/fish/conf.d/connect-iq-sdk.fish".text = ''
      if command -q connect-iq-sdk-manager
        set -l connect_iq_bin (connect-iq-sdk-manager sdk current-path --bin 2>/dev/null)
        if test -n "$connect_iq_bin" -a -d "$connect_iq_bin"
          fish_add_path --path "$connect_iq_bin"
        end
      end
    '';
  };

  home.packages = with pkgs; [
    fastfetch
    bat
    eza
  ];
}
