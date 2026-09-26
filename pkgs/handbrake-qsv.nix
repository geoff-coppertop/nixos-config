{
  handbrake,
  libva,
  libvpl,
}:
# nixpkgs' handbrake ships with neither VAAPI (unmerged upstream) nor QSV
# support. HandBrake's own build entry point (make/configure.py, confirmed
# against its source) takes --enable-qsv directly; nixpkgs' derivation
# already forwards configureFlags straight to it (confirmed against its own
# source: it already passes --disable-gtk/--enable-fdk-aac/--harden the same
# way). Three things confirmed live via CI as their own separate build
# failures, not guessed up front:
#   * libva -- libhb/handbrake/ports.h unconditionally includes <va/va_drm.h>
#     regardless of which hwaccel is used at runtime.
#   * mfxvideo.h -- HandBrake's own build normally downloads and compiles its
#     own copy of libvpl from source as a contrib module (confirmed against
#     HandBrake's contrib/libvpl/module.defs), installing it under
#     contrib/include/vpl/ and compiling with -I pointed directly at that
#     folder -- so a flat #include <mfxvideo.h> resolves against
#     contrib/include/vpl/mfxvideo.h. nixpkgs' libvpl ships that same file
#     (confirmed against upstream intel/libvpl, api/vpl/mfxvideo.h -> which
#     installs one level down from its own include/ output), so pointing
#     NIX_CFLAGS_COMPILE at libvpl's vpl/ subdirectory directly substitutes
#     for that contrib fetch, without needing network access during the
#     Nix build or a legacy Intel Media SDK dependency at all.
#   * -lva -- once headers resolved, the final link failed with "undefined
#     reference to vaTerminate" / "DSO missing from command line": libva.so
#     is found via buildInputs' search path but never listed on the actual
#     link line, since HandBrake's own module system (which normally builds
#     that line) doesn't know about a plain Nix buildInput. No undefined
#     reference to any vpl/mfx symbol appeared at this same link step, so
#     oneVPL/MSDK dispatch is runtime (dlopen), not link-time -- only libva
#     needs forcing onto the link line.
# Untested end-to-end beyond these build-time fixes -- no way to run a real
# encode from this session; verify QSV actually works before relying on it.
handbrake.overrideAttrs (old: {
  configureFlags = (old.configureFlags or []) ++ ["--enable-qsv"];
  buildInputs = (old.buildInputs or []) ++ [libva libvpl];
  # -Wno-error=format-security: overriding forces HandBrake to build from
  # source instead of nixpkgs' own cached binary, which surfaces a real
  # upstream bug nixpkgs never hits (libhb/compat.c passes a non-literal
  # format string to snprintf; --harden's -Werror=format-security turns that
  # into a build failure). Not something this override introduced or can fix
  # -- confirmed live via CI as its own failure, unrelated to qsv/libva/libvpl.
  NIX_CFLAGS_COMPILE = toString (old.NIX_CFLAGS_COMPILE or "") + " -I${libvpl}/include/vpl -Wno-error=format-security";
  # nixpkgs' handbrake sets NIX_LDFLAGS inside its own `env` attrset (to
  # "-lx265"), so appending it as a bare derivation argument here conflicts
  # (confirmed live via CI: "env attribute set cannot contain any attributes
  # passed to derivation"). Merge into env instead, preserving that value.
  # -lvpl is needed too: the link line resolved libva's undefined refs but
  # then failed the same way on MFXVideoCORE_SetHandle (confirmed live via
  # CI) -- HandBrake's module system doesn't add either plain Nix buildInput
  # to the actual link line on its own. -lva-drm is a third, separate lib
  # (libva-drm.so, not libva.so) for vaGetDisplayDRM -- same missing-DSO
  # pattern, confirmed live via CI as its own failure after -lva/-lvpl
  # resolved the first two. (First tried as -lva_drm, an underscore, which
  # ld rightly reported as no such file -- the library is libva-drm.so, a
  # hyphen, confirmed live via CI.)
  env = (old.env or {}) // {NIX_LDFLAGS = toString (old.env.NIX_LDFLAGS or "") + " -lva -lva-drm -lvpl";};
})
