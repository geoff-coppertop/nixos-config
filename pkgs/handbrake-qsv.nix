{
  handbrake,
  libvpl,
}:
# nixpkgs' handbrake ships with neither VAAPI (unmerged upstream) nor QSV
# support. HandBrake's own build entry point (make/configure.py, confirmed
# against its source) takes --enable-qsv directly; nixpkgs' derivation
# already forwards configureFlags straight to it (confirmed against its own
# source: it already passes --disable-gtk/--enable-fdk-aac/--harden the same
# way), so adding the flag plus libvpl (Intel's oneVPL, the QSV dispatch
# library HandBrake links against) is enough to build a QSV-capable
# HandBrakeCLI without patching anything. Untested end-to-end -- no way to
# build or run this from this session; verify a real QSV encode works
# before relying on it.
handbrake.overrideAttrs (old: {
  configureFlags = (old.configureFlags or []) ++ ["--enable-qsv"];
  buildInputs = (old.buildInputs or []) ++ [libvpl];
})
