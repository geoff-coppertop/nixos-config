{
  stdenvNoCC,
  fetchurl,
  unzip,
}:
# Jellyfin's plugin catalog installs a plugin by extracting its zip straight
# into a folder under <dataDir>/plugins, and a catalog zip carries its own
# meta.json (Jellyfin 10.11's PluginManager reconciles it against the catalog
# entry), so the zip's contents are the plugin as-is.
#
# The build must target a Jellyfin ABI at or below the server's version
# (nixpkgs' jellyfin is 10.11.x; this build's targetAbi is 10.11.8.0). To bump,
# take the newest matching entry from `curl -L
# https://repo.jellyfin.org/files/plugin/manifest.json` (name "Open Subtitles")
# and its hash from `nix store prefetch-file <sourceUrl>`.
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "jellyfin-plugin-opensubtitles";
  version = "24.0.0.0";

  src = fetchurl {
    url = "https://repo.jellyfin.org/files/plugin/open-subtitles/open-subtitles_${finalAttrs.version}.zip";
    hash = "sha256-pUD3/3w5cJhiwZ3wp9m1szey/IvsRuYcGUhgZzBKmYQ=";
  };

  nativeBuildInputs = [unzip];
  dontUnpack = true;

  # Fails the build if the zip isn't laid out flat with a meta.json, which
  # would otherwise leave Jellyfin silently ignoring the plugin.
  installPhase = ''
    runHook preInstall
    mkdir -p $out
    unzip -q $src -d $out
    test -e $out/Jellyfin.Plugin.OpenSubtitles.dll
    test -e $out/meta.json
    runHook postInstall
  '';
})
