{
  nixpkgs,
  home-manager,
  plasma-manager,
  agenix,
  lanzaboote,
  nix-flatpak,
  nix-vscode-extensions,
  dotfiles,
}: {
  system,
  extraModules,
}:
nixpkgs.lib.nixosSystem {
  inherit system;
  modules =
    [
      {
        nixpkgs.config.allowUnfree = true;
        nixpkgs.overlays = [nix-vscode-extensions.overlays.default];
        # VS Code rewrites ~/.vscode/argv.json on startup, clobbering the
        # home-manager-managed version. Without a backup extension, the next
        # rebuild fails on activation. Renaming to .backup lets activation
        # proceed and overwrites any previous .backup on each rebuild.
        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          backupFileExtension = "backup";
          sharedModules = [plasma-manager.homeModules.plasma-manager];
          extraSpecialArgs = {
            inherit dotfiles;
          };
        };
      }
      home-manager.nixosModules.home-manager
      agenix.nixosModules.default
      lanzaboote.nixosModules.lanzaboote
      nix-flatpak.nixosModules.nix-flatpak
    ]
    ++ extraModules;
}
