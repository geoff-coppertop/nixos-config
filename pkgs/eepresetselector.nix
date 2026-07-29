{pkgs}:
pkgs.stdenv.mkDerivation {
  pname = "gnome-shell-extension-eepresetselector";
  version = "31.1";
  src = pkgs.fetchFromGitHub {
    owner = "ulville";
    repo = "eepresetselector";
    rev = "7a2ab6ede80501e759257672f34be6e7df2a28dd"; # v31.1
    sha256 = "sha256-xpHfaZwOy9cd8lak+R8vmIMf+JeWCwSfeqyH5vxJFKM=";
  };
  nativeBuildInputs = [pkgs.glib];
  buildPhase = ''
    runHook preBuild
    glib-compile-schemas --strict --targetdir=eepresetselector@ulville.github.io/schemas/ \
      eepresetselector@ulville.github.io/schemas
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/gnome-shell/extensions/eepresetselector@ulville.github.io
    cp -r eepresetselector@ulville.github.io/. \
      $out/share/gnome-shell/extensions/eepresetselector@ulville.github.io/
    if [ -d eepresetselector@ulville.github.io/schemas ]; then
      mkdir -p $out/share/glib-2.0/schemas
      cp eepresetselector@ulville.github.io/schemas/*.xml $out/share/glib-2.0/schemas/
      glib-compile-schemas $out/share/glib-2.0/schemas/
    fi
    runHook postInstall
  '';
  meta.description = "Top-panel menu to quickly switch EasyEffects presets";
}
