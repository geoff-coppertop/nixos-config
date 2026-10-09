{
  stdenvNoCC,
  fetchurl,
  unzip,
}:
# LAPSE's catalog zip holds only the plugin DLL (no meta.json, unlike the
# OpenSubtitles one). Its targetAbi is 10.11.0.0 and its README asks for 10.11.11
# or newer. To bump, take the newest entry from
# https://raw.githubusercontent.com/Schwponaco-org/lapse-jellyfin-plugin/main/manifest.json
# and its hash from `nix store prefetch-file <sourceUrl>`.
stdenvNoCC.mkDerivation {
  pname = "jellyfin-plugin-lapse";
  version = "2.1.0.0";

  src = fetchurl {
    url = "https://github.com/Schwponaco-org/lapse-jellyfin-plugin/releases/download/v2.1.0/lapse-jellyfin-plugin-v2.1.0.zip";
    hash = "sha256-jtzG8OliqWTBfglqvJMEUDk3L4HcdWlKkTAjW18SWOM=";
  };

  nativeBuildInputs = [unzip];
  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    unzip -q $src -d $out
    test -e $out/Jellyfin.Plugin.Lapse.dll
    runHook postInstall
  '';
}
