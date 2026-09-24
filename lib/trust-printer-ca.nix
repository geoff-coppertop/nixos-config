# Appends a CA cert to a Bambu-family slicer's bundled printer.cer PEM
# bundle. overrideAttrs would invalidate the upstream binary-cache
# substitute for the whole package -- a from-source C++ rebuild taking
# tens of minutes, for a one-file change -- since it produces a
# differently-hashed derivation with the same build phases. This instead
# copies the already-built (substituted) output and patches just the one
# file, so only that copy runs locally.
#
# Upstream ships printer.cer with no trailing newline, so this adds one
# first — otherwise the two blocks merge into one unparseable line
# ("bad end line" from OpenSSL's PEM parser, confirmed live).
{
  pkgs,
  name,
  package,
  certPath,
  caFile,
}:
pkgs.runCommand name {} ''
  cp -r ${package} $out
  chmod -R u+w $out
  printf '\n' >> ${certPath}
  cat ${caFile} >> ${certPath}
''
