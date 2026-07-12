{
  imports = [./configuration.nix];
  home-manager.users.thomasga.imports = [./home/thomasga.nix];
  home-manager.users.thomasar.imports = [./home/thomasar.nix];
}
