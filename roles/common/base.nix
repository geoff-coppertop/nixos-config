{ lib, pkgs, ... }:

{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  time.timeZone = "America/Edmonton";

  fonts.packages = with pkgs; [
    nerdfonts
  ];

  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "google-chrome"
      "steam"
      "steam-original"
      "steam-run"
    ];
}
