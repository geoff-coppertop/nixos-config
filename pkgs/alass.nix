{
  stdenvNoCC,
  fetchurl,
}:
# Upstream's release asset is a statically linked x86_64 Linux executable (no
# interpreter, so no patching needed on NixOS). The pinned nixpkgs doesn't ship
# alass. To bump, take the asset URL from
# https://github.com/kaegi/alass/releases and its hash from
# `nix store prefetch-file <url>`.
stdenvNoCC.mkDerivation {
  pname = "alass";
  version = "2.0.0";

  src = fetchurl {
    url = "https://github.com/kaegi/alass/releases/download/v2.0.0/alass-linux64";
    hash = "sha256-e9C5rn4DXTupQOrP+yEkNhTfNiMdR/IfC0zkIAGrf80=";
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -D -m755 $src $out/bin/alass
    runHook postInstall
  '';

  meta.platforms = ["x86_64-linux"];
}
