{
  lib,
  stdenv,
  fetchFromGitHub,
  kernel,
}:
# Out-of-tree force-feedback driver for SIMAGIC wheelbases
# (github.com/JacKeTUs/simagic-ff), built against the host kernel and loaded
# via boot.extraModulePackages in modules/simagic.nix. FFB requires wheelbase
# firmware post-v159 / Simpro v2 (flashed once from Windows or a USB-passthrough
# VM — see hosts/stargazer/README.md).
#
# Pinned from CI's build-job hash mismatch (PR #98, run 30373000232): the
# `master` branch ref fetched successfully; this is the reported source hash.
# `master` is a moving ref, not a tag — no tagged release was findable for this
# project from this session's scoped GitHub access. This hash pins today's
# commit; a future upstream push to master will hash-mismatch again (the same
# oracle mechanism applies) rather than silently pull in new code.
stdenv.mkDerivation {
  pname = "simagic-ff";
  version = "0-unstable-2026-07-28";

  src = fetchFromGitHub {
    owner = "JacKeTUs";
    repo = "simagic-ff";
    rev = "master";
    hash = "sha256-kFXyADTapJo+jZd2UqTMEmG6AA7+lmJZeKNd2n1jwOc=";
  };

  nativeBuildInputs = kernel.moduleBuildDependencies;

  # The upstream Makefile's default target hardcodes
  # `/lib/modules/$(shell uname -r)/build`, which doesn't exist in the Nix
  # sandbox (its uname doesn't match the linux-${kernel.modDirVersion}-dev
  # package being built against — CI: "No such file or directory"). Bypass
  # that wrapper and invoke kbuild's own external-module target directly,
  # which every out-of-tree module's Makefile calls internally regardless of
  # how its own default target locates the kernel tree.
  buildPhase = ''
    runHook preBuild
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build M=$PWD modules
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/modules/${kernel.modDirVersion}/extra"
    find . -name '*.ko' -exec cp {} "$out/lib/modules/${kernel.modDirVersion}/extra/" \;
    runHook postInstall
  '';

  meta = {
    description = "Force feedback driver for SIMAGIC steering wheelbases";
    homepage = "https://github.com/JacKeTUs/simagic-ff";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
  };
}
