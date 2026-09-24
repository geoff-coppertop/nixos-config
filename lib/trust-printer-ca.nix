# Appends a CA cert to a Bambu-family slicer's bundled printer.cer PEM
# bundle. Upstream ships that file with no trailing newline, so this adds
# one first — otherwise the two blocks merge into one unparseable line
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
