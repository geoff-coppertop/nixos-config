{
  description = "NixOS config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    pre-commit.url = "github:cachix/pre-commit-hooks.nix";
    pre-commit.inputs.nixpkgs.follows = "nixpkgs";

    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";
    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";
    nix-vscode-extensions.inputs.nixpkgs.follows = "nixpkgs";

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.0.0";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        pre-commit.follows = "pre-commit";
      };
    };

    # Shared fish/git "look and feel", consumed directly by home-manager
    # here (home.file.source) and by devcontainer-features' shell-baseline
    # feature. Not a flake; pinned by flake.lock like every other input.
    dotfiles = {
      url = "github:geoff-coppertop/dotfiles";
      flake = false;
    };
  };

  outputs = {
    nixpkgs,
    disko,
    home-manager,
    agenix,
    lanzaboote,
    nix-flatpak,
    nix-vscode-extensions,
    nixos-wsl,
    dotfiles,
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

    nixApps = import ./lib/apps.nix {
      inherit pkgs agenixCli;
    };

    mkNixosSystem = import ./lib/nixos-system.nix {
      inherit nixpkgs home-manager agenix lanzaboote nix-flatpak nix-vscode-extensions dotfiles;
    };

    mkHomeConfig = {
      user,
      machine,
      hostSystem,
    }:
      home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = hostSystem;
          config.allowUnfree = true;
          overlays = [nix-vscode-extensions.overlays.default];
        };
        extraSpecialArgs = {
          inherit dotfiles;
        };
        modules = [
          ./hosts/${machine}/home/${user}.nix
          {
            home.username = user;
            home.homeDirectory = "/home/${user}";
          }
        ];
      };
  in {
    devShells.${system}.default = devShell;

    checks.${system} = checks;

    apps.${system} = nixApps;

    nixosConfigurations = {
      "enterprise-d" = mkNixosSystem {
        system = "x86_64-linux";
        extraModules = [
          ./hosts/enterprise-d
          {home-manager.users.thomasga.programs.firefox.configPath = ".mozilla/firefox";}
          disko.nixosModules.disko
        ];
      };

      "holodeck-01" = mkNixosSystem {
        system = "x86_64-linux";
        extraModules = [
          ./hosts/holodeck-01
          nixos-wsl.nixosModules.default
        ];
      };

      "defiant" = mkNixosSystem {
        system = "aarch64-linux";
        extraModules = [./hosts/defiant];
      };
    };

    homeConfigurations = {
      "thomasga@enterprise-d" = mkHomeConfig {
        user = "thomasga";
        machine = "enterprise-d";
        hostSystem = "x86_64-linux";
      };
      "thomasga@holodeck-01" = mkHomeConfig {
        user = "thomasga";
        machine = "holodeck-01";
        hostSystem = "x86_64-linux";
      };
      "thomasga@defiant" = mkHomeConfig {
        user = "thomasga";
        machine = "defiant";
        hostSystem = "aarch64-linux";
      };
    };
  };
}
