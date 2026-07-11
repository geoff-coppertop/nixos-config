# Obsidian, managed declaratively via home-manager's `programs.obsidian`
# module. Enabling it makes Nix own everything under the vault's `.obsidian/`
# that is declared here — in particular `community-plugins.json` is written
# from the `communityPlugins` list below, so EVERY plugin you want enabled
# must appear here (toggling one in Obsidian's UI won't survive a rebuild).
#
# The module installs `pkgs.obsidian` itself (via `programs.obsidian.package`),
# so it is intentionally not listed in `home.packages`.
{pkgs, ...}: let
  mkObsidianPlugin = import ../../lib/obsidian-plugin.nix {inherit pkgs;};

  # draw.io plugin (somesanity/draw-io-obsidian, id "drawio"): edit .drawio
  # diagrams embedded in notes inside Obsidian, fully offline. See README
  # § draw.io And Obsidian for the .drawio file-association side of this.
  drawio = mkObsidianPlugin {
    owner = "somesanity";
    repo = "draw-io-obsidian";
    version = "3.1.1";
    id = "drawio";
    # main.js is a release-only build artifact and could not be fetched in the
    # build environment this was authored in; TOFU it on the first build (the
    # build fails printing the real hash, or run
    # `nix store prefetch-file https://github.com/somesanity/draw-io-obsidian/releases/download/3.1.1/main.js`).
    mainHash = pkgs.lib.fakeHash;
    manifestHash = "sha256-HgmyiKukX/qtXkxuq/lPajBRKXAYiI/1rMGZtW/cuyg=";
    stylesHash = "sha256-V16rZ40KcyFQfGNIX5Ufr9Eb6nAdl6rG+xZ5EVq+yJU=";
  };
in {
  programs.obsidian = {
    enable = true;

    vaults.main = {
      # Vault directory relative to $HOME. Sensible default; override if your
      # vault lives elsewhere — a wrong value makes the module populate a stray
      # empty vault at this path instead of the real one.
      target = "Documents/Obsidian";

      settings.communityPlugins = [drawio];
    };
  };
}
