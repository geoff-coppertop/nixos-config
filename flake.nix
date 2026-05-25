{
  description = "NixOS config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    disko.url = "github:nix-community/disko";
    home-manager.url = "github:nix-community/home-manager";
    agenix.url = "github:ryantm/agenix";
    pre-commit.url = "github:cachix/pre-commit-hooks.nix";

    # Add nix-flatpak input here
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
      config.allowUnfree = true; # Standardize unfree here as well
    };
    src = pkgs.lib.cleanSource ./.;
    agenixCli = agenix.packages.${system}.default;
    checks = import ./lib/checks.nix {
      inherit pkgs src;
    };
    devShell = import ./lib/devshell.nix {
      inherit pkgs agenixCli;
    };

    # We wrap the imported secretApps to add the missing 'meta' attributes
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
  in {
    devShells.${system}.default = devShell;

    checks.${system} = checks;

    apps.${system} = secretApps;

    nixosConfigurations.framework = nixpkgs.lib.nixosSystem {
      inherit system;

      modules = [
        ./hosts/framework

        {
          nixpkgs.config.allowUnfree = true;

          # SILENCE FIREFOX WARNING:
          # This sets the config path to the new XDG standard
          home-manager.users.thomasga.programs.firefox.configPath = ".mozilla/firefox";
          # Note: Set to ".mozilla/firefox" to keep current behavior WITHOUT the warning,
          # OR set to "${config.xdg.configHome}/mozilla/firefox" to migrate.
        }

        disko.nixosModules.disko
        home-manager.nixosModules.home-manager
        agenix.nixosModules.default
        lanzaboote.nixosModules.lanzaboote

        nix-flatpak.nixosModules.nix-flatpak
      ];
    };
  };
}
