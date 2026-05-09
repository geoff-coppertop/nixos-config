{ lib, ... }:

{
  options.custom.cli.shell = lib.mkOption {
    type = lib.types.enum [ "fish" "zsh" ];
    default = "fish";
    description = "Default interactive shell for this Home Manager profile.";
  };

  imports = [
    ./fish.nix
    ./fzf.nix
    ./git.nix
    ./modern-unix.nix
    ./starship.nix
    ./zsh.nix
    ./zoxide.nix
  ];
}
