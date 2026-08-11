# The community "wiim" Home Assistant integration (github.com/mjcumming/wiim),
# installed via services.home-assistant.customComponents rather than
# extraComponents -- it is a third-party custom_components package (HACS),
# not part of Home Assistant core, so nixpkgs' component-packages.nix has no
# entry for it. See docs/smart-home.md § Wiim and hosts/reliant/README.md
# § Known Gotchas for why this replaces the core "linkplay" integration for
# Wiim devices.
{
  lib,
  buildHomeAssistantComponent,
  fetchFromGitHub,
  home-assistant,
}:
buildHomeAssistantComponent rec {
  owner = "mjcumming";
  domain = "wiim";
  version = "1.0.95";

  src = fetchFromGitHub {
    inherit owner;
    repo = "wiim";
    tag = "v${version}";
    # NAR hash of the unpacked source tree, as reported by Nix's own
    # hash-mismatch error from a real nixos-rebuild switch attempt against
    # reliant (no local Nix toolchain was available to compute it directly).
    hash = "sha256-Gfetibyoy/BMuT6yNxLs5LGMc8YYxqy9BWT6PbgHdVE=";
  };

  dependencies = [
    (import ./pywiim.nix {inherit lib home-assistant;})
  ];

  meta = rec {
    description = "WiiM (LinkPlay) audio integration for Home Assistant, with multiroom support";
    homepage = "https://github.com/mjcumming/wiim";
    changelog = "${homepage}/releases/tag/v${version}";
    license = lib.licenses.mit;
  };
}
