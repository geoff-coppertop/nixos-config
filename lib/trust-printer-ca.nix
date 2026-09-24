# Appends a CA cert to a Bambu-family slicer's bundled printer.cer PEM
# bundle, and wraps the binary with SSL_CERT_FILE. Upstream's own
# OpenSSL init (separate from the printer.cer trust store) hardcodes a
# nonexistent build-machine path
# (/home/lane.wei/dep_linux_new/usr/local/cert.pem, confirmed via
# strace) and surfaces that ENOENT as a misleading "certificate has
# expired" dialog at startup -- the same root cause OrcaSlicer's own
# AppImage issue #5333 documents, SSL_CERT_FILE the fix suggested there.
#
# A copy-and-patch approach (skip overrideAttrs, cp the already-built
# output, edit the file) was tried to avoid a full rebuild, but doesn't
# work: the binary bakes in an absolute resource-directory path at
# compile time, so a copy still loads printer.cer from the original,
# unpatched derivation regardless of where the copy sits. overrideAttrs
# rebuilds so the binary compiles in its own new $out.
#
# Upstream ships printer.cer with no trailing newline, so this adds one
# first — otherwise the two blocks merge into one unparseable line
# ("bad end line" from OpenSSL's PEM parser, confirmed live).
{
  pkgs,
  package,
  certPath,
  caFile,
  binName,
}:
package.overrideAttrs (old: {
  nativeBuildInputs = (old.nativeBuildInputs or []) ++ [pkgs.makeWrapper];
  postInstall =
    (old.postInstall or "")
    + ''
      chmod u+w ${certPath}
      printf '\n' >> ${certPath}
      cat ${caFile} >> ${certPath}
    '';
  postFixup =
    (old.postFixup or "")
    + ''
      wrapProgram $out/bin/${binName} \
        --set SSL_CERT_FILE ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
    '';
})
