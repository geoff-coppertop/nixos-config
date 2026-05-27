{
  description = "NixOS config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    disko.url = "github:nix-community/disko";
    home-manager.url = "github:nix-community/home-manager";
    agenix.url = "github:ryantm/agenix";
    pre-commit.url = "github:cachix/pre-commit-hooks.nix";

    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";

    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    pre-commit.inputs.nixpkgs.follows = "nixpkgs";

    lanzaboote = {
      inputs = {
        nixpkgs.follows = "nixpkgs";
        pre-commit.follows = "pre-commit";
      };
      url = "github:nix-community/lanzaboote/v1.0.0";
    };
  };

  outputs = {
    nixpkgs,
    disko,
    home-manager,
    agenix,
    lanzaboote,
    nix-flatpak,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
    src = pkgs.lib.cleanSource ./.;
    agenixCli = agenix.packages.${system}.default;
    checks = import ./lib/checks.nix {
      inherit pkgs src;
    };
    devShell = import ./lib/devshell.nix {
      inherit pkgs agenixCli;
    };

    rawSecretApps = import ./lib/secret-apps.nix {
      inherit pkgs agenixCli;
    };

    secretApps = {
      secret-edit =
        rawSecretApps.secret-edit
        // {
          meta = {description = "Edit encrypted agenix secrets";};
        };
      secret-rekey =
        rawSecretApps.secret-rekey
        // {
          meta = {description = "Rekey agenix secrets with new host keys";};
        };
    };

    mkNixosSystem = import ./lib/nixos-system.nix {
      inherit nixpkgs system home-manager agenix;
    };
  in {
    devShells.${system}.default = devShell;

    checks.${system} = checks;

    apps.${system} = secretApps;

    nixosConfigurations."enterprise-d" = mkNixosSystem [
      ./hosts/enterprise-d
      {home-manager.users.thomasga.programs.firefox.configPath = ".mozilla/firefox";}
      disko.nixosModules.disko
      lanzaboote.nixosModules.lanzaboote
      nix-flatpak.nixosModules.nix-flatpak
    ];
  };
}
