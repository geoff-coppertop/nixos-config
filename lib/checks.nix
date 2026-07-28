{
  pkgs,
  src,
}: {
  alejandra =
    pkgs.runCommand "alejandra-check" {
      nativeBuildInputs = [pkgs.alejandra];
    } ''
      cp -r ${src} source
      chmod -R +w source
      cd source
      alejandra --check .
      touch $out
    '';

  statix =
    pkgs.runCommand "statix-check" {
      nativeBuildInputs = [pkgs.statix];
    } ''
      cp -r ${src} source
      chmod -R +w source
      cd source
      statix check .
      touch $out
    '';

  deadnix =
    pkgs.runCommand "deadnix-check" {
      nativeBuildInputs = [pkgs.deadnix];
    } ''
      cp -r ${src} source
      chmod -R +w source
      cd source
      deadnix --fail .
      touch $out
    '';

  markdownlint =
    pkgs.runCommand "markdownlint-check" {
      nativeBuildInputs = [pkgs.markdownlint-cli];
    } ''
      cp -r ${src} source
      chmod -R +w source
      cd source
      find . -name '*.md' -print0 | xargs -0 -r markdownlint
      touch $out
    '';

  # Catches a .nix file that no default.nix imports — silently never evaluated,
  # so nothing else in the toolchain reports it. There is no .git in here (src
  # is cleanSource'd), which the script handles by walking the filesystem.
  orphanNix =
    pkgs.runCommand "orphan-nix-check" {
      nativeBuildInputs = [pkgs.python3];
    } ''
      cp -r ${src} source
      chmod -R +w source
      python3 source/tools/check_orphan_nix.py
      touch $out
    '';

  # A check that cannot fail is worth nothing. This runs check_orphan_nix
  # against synthetic fixture trees under a tempdir, not against this repo —
  # it proves the checker still catches an unimported file and still passes a
  # clean one, without ever touching this repo's own working tree.
  orphanNixSelfTest =
    pkgs.runCommand "orphan-nix-self-test" {
      nativeBuildInputs = [pkgs.python3];
    } ''
      cp -r ${src} source
      chmod -R +w source
      python3 source/tools/test_check_orphan_nix.py
      touch $out
    '';
}
