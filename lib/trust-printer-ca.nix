# Appends a CA cert to a Bambu-family slicer's bundled printer.cer PEM
# bundle. A copy-and-patch approach (skip overrideAttrs, cp the already-
# built output, edit the file) was tried to avoid a full rebuild, but
# doesn't work: the binary bakes in an absolute resource-directory path
# at compile time, so a copy still loads printer.cer from the original,
# unpatched derivation regardless of where the copy sits. overrideAttrs
# rebuilds so the binary compiles in its own new $out.
#
# Upstream ships printer.cer with no trailing newline, so this adds one
# first — otherwise the two blocks merge into one unparseable line
# ("bad end line" from OpenSSL's PEM parser, confirmed live).
{
  package,
  certPath,
  caFile,
}:
package.overrideAttrs (old: {
  postInstall =
    (old.postInstall or "")
    + ''
      chmod u+w ${certPath}
      printf '\n' >> ${certPath}
      cat ${caFile} >> ${certPath}
    '';
})
