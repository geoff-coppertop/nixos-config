{
  imports = [
    ./configuration.nix
  ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;

    users = {
      thomasga = import ../../users/thomasga;
    };
  };
}
