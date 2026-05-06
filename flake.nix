{
  description = "NixOS config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    disko.url = "github:nix-community/disko";
    home-manager.url = "github:nix-community/home-manager";
    agenix.url = "github:ryantm/agenix";
    lanzaboote.url = "github:nix-community/lanzaboote";

    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    lanzaboote.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, disko, home-manager, agenix, lanzaboote, ... }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
    };
    src = pkgs.lib.cleanSource ./.;
  in {
    devShells.${system}.default = pkgs.mkShell {
      packages = with pkgs; [
        alejandra
        deadnix
        nodePackages.markdownlint-cli
        pre-commit
        statix
      ];
    };

    checks.${system} = {
      alejandra = pkgs.runCommand "alejandra-check" {
        nativeBuildInputs = [ pkgs.alejandra ];
      } ''
        cp -r ${src} source
        chmod -R +w source
        cd source
        alejandra --check .
        touch $out
      '';

      statix = pkgs.runCommand "statix-check" {
        nativeBuildInputs = [ pkgs.statix ];
      } ''
        cp -r ${src} source
        chmod -R +w source
        cd source
        statix check .
        touch $out
      '';

      deadnix = pkgs.runCommand "deadnix-check" {
        nativeBuildInputs = [ pkgs.deadnix ];
      } ''
        cp -r ${src} source
        chmod -R +w source
        cd source
        deadnix --fail .
        touch $out
      '';

      markdownlint = pkgs.runCommand "markdownlint-check" {
        nativeBuildInputs = [ pkgs.nodePackages.markdownlint-cli ];
      } ''
        cp -r ${src} source
        chmod -R +w source
        cd source
        find . -name '*.md' -print0 | xargs -0 -r markdownlint
        touch $out
      '';
    };

    nixosConfigurations.framework = nixpkgs.lib.nixosSystem {
      inherit system;

      modules = [
        ./hosts/framework/configuration.nix
        ./hosts/framework/disko.nix

        disko.nixosModules.disko
        home-manager.nixosModules.home-manager
        agenix.nixosModules.default
        lanzaboote.nixosModules.lanzaboote

        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;

            users = {
              thomasga = import ./users/thomasga;
            };
          };
        }
      ];
    };
  };
}
