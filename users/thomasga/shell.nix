{pkgs, ...}: {
  custom.cli.shell = "fish";

  # fish_greeting/ls/ll/lt functions and aliases now come from
  # geoff-coppertop/dotfiles, shared with devcontainer-features. The Connect IQ
  # SDK PATH shim is machine-specific dev tooling, so it stays home-manager-owned
  # as a fish conf.d drop-in (sourced regardless of how config.fish is provided)
  # rather than going into the shared dotfiles config.fish.
  home.file.".config/fish/conf.d/connect-iq-sdk.fish".text = ''
    if command -q connect-iq-sdk-manager
      set -l connect_iq_bin (connect-iq-sdk-manager sdk current-path --bin 2>/dev/null)
      if test -n "$connect_iq_bin" -a -d "$connect_iq_bin"
        fish_add_path --path "$connect_iq_bin"
      end
    end
  '';

  home.packages = with pkgs; [
    fastfetch
    bat
    eza
  ];
}
