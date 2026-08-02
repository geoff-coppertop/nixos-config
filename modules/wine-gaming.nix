{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf;
in {
  options.custom.wineGaming.enable = mkEnableOption "Wine/Proton tooling for standalone Windows games (DCS, VoiceAttack, SimHub)";

  # Tooling only. The actual DCS / VoiceAttack / VAICOM / SimHub install is a
  # runtime runbook on the machine (see hosts/stargazer/README.md); none of it
  # is Nix-declarable. umu-launcher runs standalone DCS on official Proton with
  # an explicit WINEPREFIX; lutris carries the maintained DCS install script.
  config = mkIf config.custom.wineGaming.enable {
    environment.systemPackages = let
      # lutris pulls openldap in only as a transitive lib inside its bundled
      # 32-bit FHS environment — nothing here runs it as a server. Its test
      # suite includes a timing-based replication check
      # (test017-syncreplication-refresh) that flakes under CI's
      # shared-runner scheduling. Scoped via a local pkgs.extend (not
      # nixpkgs.overlays) so it shadows openldap only inside lutris's own
      # build closure — any other consumer on this host, e.g. a future
      # services.openldap, still gets the real package with checks intact.
      lutrisPkgs = pkgs.extend (_final: prev: {
        openldap = prev.openldap.overrideAttrs (_: {doCheck = false;});
      });
    in
      (with pkgs; [
        umu-launcher
        protonup-qt
        winetricks
        protontricks
        wineWowPackages.stable
        mangohud
        gamescope
      ])
      ++ [lutrisPkgs.lutris];
  };
}
