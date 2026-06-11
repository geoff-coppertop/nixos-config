{
  config,
  lib,
  pkgs,
  ...
}: let
  plugin = pkgs.callPackage ../../pkgs/obsidian-local-rest-api.nix {};
  pluginDir = "${config.custom.obsidian.vaultPath}/.obsidian/plugins/obsidian-local-rest-api";
in {
  options.custom.obsidian.vaultPath = lib.mkOption {
    type = lib.types.str;
    default = "${config.home.homeDirectory}/Documents/obsidian";
    description = "Path to the primary Obsidian vault";
  };

  config = {
    # Copy plugin files rather than symlinking so Obsidian can write data.json
    # (API key and settings) into the same directory without hitting a read-only
    # Nix store path.
    home.activation.obsidianLocalRestApiPlugin = lib.hm.dag.entryAfter ["writeBoundary"] ''
      $DRY_RUN_CMD mkdir -p "${pluginDir}"
      for f in main.js manifest.json styles.css; do
        src="${plugin}/$f"
        if [ -f "$src" ]; then
          $DRY_RUN_CMD install -m 644 "$src" "${pluginDir}/$f"
        fi
      done
    '';
  };
}
