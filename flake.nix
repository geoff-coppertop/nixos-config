{
  description = "NixOS config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    agenix = {
      url = "github:ryantm/agenix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        # agenix's own home-manager input is only used by its Darwin
        # integration check and example homeConfiguration, neither of which
        # we consume; its homeManagerModules.age output is static module code
        # independent of which home-manager version built it. Following our
        # pin instead of letting it fetch its own collapses the flake.lock
        # split that produced a second, unused "home-manager" node (our own
        # input actually resolves to "home-manager_2") — the exact trap that
        # made an earlier bump silently miss the version our
        # home-manager.users config evaluates against.
        home-manager.follows = "home-manager";
      };
    };
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
      url = "github:nix-community/lanzaboote/v1.1.0";
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
    self,
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
    checks =
      import ./lib/checks.nix {
        inherit pkgs src;
      }
      // {
        # Evaluated, not built — so `nix flake check --no-build` catches it.
        modules-inert = import ./lib/module-inertness.nix {
          inherit pkgs;
          modulesDir = ./modules;
          # The probe imports modules/ through the same base module list every
          # host uses (home-manager, agenix, lanzaboote, nix-flatpak), so the
          # options our modules reference are declared exactly as they are on a
          # real host. It deliberately sets no custom.* option.
          probe = mkNixosSystem {
            inherit system;
            extraModules = [
              ./modules
              {
                boot.loader.grub.enable = false;
                fileSystems."/" = {
                  device = "none";
                  fsType = "tmpfs";
                };
                networking.hostName = "module-inertness-probe";
                system.stateVersion = "25.11";
              }
            ];
          };
        };
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
          config = {
            allowUnfree = true;
          };
          overlays = [nix-vscode-extensions.overlays.default];
        };
        extraSpecialArgs = {
          inherit dotfiles;
          # gnome.nix/kde.nix declare `osConfig ? null` and treat null as "not
          # running under the NixOS integration module" (falls back to
          # "gnome"). That default only fires when the module system supplies
          # no value for osConfig at all; it does not protect against a cycle
          # if some other module conditionally contributes its own
          # `_module.args` based on config that participates in the same
          # evaluation (e.g. a DE module gating an extra specialArg on its own
          # enable option). Passing osConfig = null explicitly here removes
          # the standalone (non-NixOS) path's dependence on args-merging
          # fallback resolution entirely.
          osConfig = null;
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

    packages.${system} = {
      # Reliant's Nix-declared automations and helpers, rendered to a
      # standalone configuration.yaml. CI feeds this to `hass --script
      # check_config` so a malformed automation (bad trigger platform, broken
      # choose/action, unknown service) or a broken input_* helper definition
      # fails the build instead of only surfacing when Home Assistant loads it
      # at runtime — Nix serializes this config verbatim and never
      # schema-checks the Home Assistant side itself. Scoped to "automation
      # manual" and "input_datetime" (not the whole config) to keep the check
      # focused on this file's own declarative content and free of
      # config-entry/!include noise from the rest of the setup.
      ha-config-reliant = let
        haConfig = self.nixosConfigurations.reliant.config.services.home-assistant.config;
      in
        (pkgs.formats.yaml {}).generate "configuration.yaml" {
          "automation manual" = haConfig."automation manual";
          input_datetime = haConfig.input_datetime or {};
        };

      # home-assistant, for validating the automations with check_config in CI.
      # `hass` runs standalone here — HA core is on its wrapper's PYTHONPATH —
      # but HA's `--script` runner (homeassistant/scripts/__init__.py) also
      # unconditionally requires colorlog==6.10.1 (an exact-version pin in
      # homeassistant/scripts/check_config.py's REQUIREMENTS) and, if it isn't
      # already importable at that exact version, shells out to
      # `sys.executable -m uv pip install` to fetch it. That install always
      # fails here regardless of network access: nixpkgs' Python interpreters
      # carry an EXTERNALLY-MANAGED marker, and uv refuses outright to modify
      # the read-only /nix/store rather than just installing to --target (an
      # actual CI run confirmed this — "The interpreter ... is externally
      # managed ... tries to modify the immutable /nix/store filesystem").
      # ha-check-colorlog below pre-supplies the exact pinned version instead,
      # so is_installed() is satisfied and install_package() never runs. Base
      # HA (no extraComponents) is enough: the check is scoped to the
      # automations, which use only core triggers/actions.
      ha-check-hass = pkgs.home-assistant;

      # colorlog, pinned to the exact version homeassistant/scripts/
      # check_config.py requires (REQUIREMENTS = ("colorlog==6.10.1",)) rather
      # than whatever nixpkgs' own colorlog attribute currently carries —
      # confirmed those two drift independently (nixpkgs has already moved to
      # 6.11.0, which fails HA's exact `==6.10.1` check despite being newer).
      # Built directly from the upstream wheel so this stays correct
      # regardless of nixpkgs' colorlog version; sha256 independently verified
      # against the file downloaded from PyPI, not just copied from its API.
      ha-check-colorlog = pkgs.home-assistant.python3Packages.buildPythonPackage {
        pname = "colorlog";
        version = "6.10.1";
        format = "wheel";
        src = pkgs.fetchurl {
          url = "https://files.pythonhosted.org/packages/6d/c1/e419ef3723a074172b68aaa89c9f3de486ed4c2399e2dbd8113a4fdcaf9e/colorlog-6.10.1-py3-none-any.whl";
          hash = "sha256-LX6DSCkZSK9mEiz/AGyfjaYlXSJOfPjjfY3i3zutjJw=";
        };
        doCheck = false;
      };
    };

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

      "excelsior" = mkNixosSystem {
        system = "x86_64-linux";
        extraModules = [
          ./hosts/excelsior
          disko.nixosModules.disko
        ];
      };

      "reliant" = mkNixosSystem {
        system = "x86_64-linux";
        extraModules = [
          ./hosts/reliant
          disko.nixosModules.disko
        ];
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

      "thomasga@excelsior" = mkHomeConfig {
        user = "thomasga";
        machine = "excelsior";
        hostSystem = "x86_64-linux";
      };

      "thomasga@reliant" = mkHomeConfig {
        user = "thomasga";
        machine = "reliant";
        hostSystem = "x86_64-linux";
      };
    };
  };
}
