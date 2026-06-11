{
  nixpkgs,
  home-manager,
  agenix,
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
        # VS Code rewrites ~/.vscode/argv.json on startup, clobbering the
        # home-manager-managed version. Without a backup extension, the next
        # rebuild fails on activation. Renaming to .backup lets activation
        # proceed and overwrites any previous .backup on each rebuild.
        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          backupFileExtension = "backup";
        };
      }
      home-manager.nixosModules.home-manager
      agenix.nixosModules.default
    ]
    ++ extraModules;
}
