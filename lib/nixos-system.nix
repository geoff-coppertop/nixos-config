{
  nixpkgs,
  system,
  home-manager,
  agenix,
}: extraModules:
nixpkgs.lib.nixosSystem {
  inherit system;
  modules =
    [
      {
        nixpkgs.config.allowUnfree = true;
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
      }
      home-manager.nixosModules.home-manager
      agenix.nixosModules.default
    ]
    ++ extraModules;
}
