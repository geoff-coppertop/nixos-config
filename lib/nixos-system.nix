{
  nixpkgs,
  home-manager,
  agenix,
  lanzaboote,
  nix-flatpak,
  nix-vscode-extensions,
  dotfiles,
  cosmic-manager,
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
        nixpkgs.overlays = [
          nix-vscode-extensions.overlays.default
          (import ../overlays/paho-mqtt-skip-flaky-tests.nix)
        ];
        # VS Code rewrites ~/.vscode/argv.json on startup, clobbering the
        # home-manager-managed version. Without a backup extension, the next
        # rebuild fails on activation. Renaming to .backup lets activation
        # proceed and overwrites any previous .backup on each rebuild.
        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          backupFileExtension = "backup";
          extraSpecialArgs = {
            inherit dotfiles;
          };
          # COSMIC declarative config module. Adds the wayland.desktopManager.cosmic
          # option tree to every home-manager user; inert unless enabled, which
          # only happens under custom.desktop.environment = "cosmic".
          sharedModules = [cosmic-manager.homeManagerModules.default];
        };
      }
      home-manager.nixosModules.home-manager
      agenix.nixosModules.default
      lanzaboote.nixosModules.lanzaboote
      nix-flatpak.nixosModules.nix-flatpak
    ]
    ++ extraModules;
}
