# Builds an Obsidian community-plugin package from a pinned GitHub release.
#
# Community plugins publish their built artifacts (main.js, manifest.json and,
# optionally, styles.css) as GitHub *release assets* — they are not committed
# to the plugin repo — so each asset is fetched individually and pinned by
# hash. The result is a directory suitable for `programs.obsidian`'s
# `communityPlugins.*.pkg`, which links it into `<vault>/.obsidian/plugins/<id>/`.
#
# Adding a plugin is one call: owner/repo/version/id plus the three asset
# hashes. Obtain the hashes by building once with `pkgs.lib.fakeHash` and
# copying the "got:" value nix reports, or with
# `nix store prefetch-file <asset-url>`.
{pkgs}: {
  owner,
  repo,
  version,
  id,
  mainHash,
  manifestHash,
  stylesHash ? null,
}: let
  inherit (pkgs) lib;
  asset = name: hash:
    pkgs.fetchurl {
      url = "https://github.com/${owner}/${repo}/releases/download/${version}/${name}";
      inherit hash;
    };
in
  pkgs.stdenvNoCC.mkDerivation {
    pname = "obsidian-plugin-${id}";
    inherit version;
    dontUnpack = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp ${asset "main.js" mainHash} "$out/main.js"
      cp ${asset "manifest.json" manifestHash} "$out/manifest.json"
      ${lib.optionalString (stylesHash != null) ''cp ${asset "styles.css" stylesHash} "$out/styles.css"''}
      runHook postInstall
    '';

    # `programs.obsidian` reads this to name the plugin directory (falling back
    # to manifest.json's `id`/`name`); it must match the manifest id.
    passthru.manifestId = id;
  }
