# Appends a CA cert to printer.cer and wraps the binary with SSL_CERT_FILE
# (upstream's OpenSSL init hardcodes a dead build-machine path, surfacing as
# a false "certificate has expired" dialog -- same root cause as OrcaSlicer
# issue #5333), GDK_BACKEND=x11 (works around a Wayland stuck-"always on
# top" dialog bug -- OrcaSlicer PR #15250), and GTK_THEME=Adwaita:dark (the
# apps' own dark-mode setting only themes their own panels, not GTK chrome).
#
# Uses runCommand on the stock nixpkgs build instead of overrideAttrs, which
# would force a from-source rebuild with no cache.nixos.org substitute.
# Giving this derivation the stock package's name keeps both store paths
# the same length, so the stock path can be byte-substituted for this one's
# $out everywhere -- including inside the compiled binary, which bakes in
# its resources-directory path at compile time (SLIC3R_FHS=ON). A plain
# `cp -r` alone leaves that baked-in path pointing at the unpatched
# printer.cer.
#
# printer.cer ships with no trailing newline; without adding one first, the
# appended block merges into an unparseable line for OpenSSL's PEM parser.
{
  pkgs,
  package,
  certPath,
  caFile,
  binName,
}: let
  patchSelfReferences = pkgs.writeText "patch-self-references.py" ''
    import pathlib, sys

    old, new, root = sys.argv[1].encode(), sys.argv[2].encode(), sys.argv[3]
    assert len(old) == len(new), "store paths must be the same length"
    for path in pathlib.Path(root).rglob("*"):
        if not path.is_file() or path.is_symlink():
            continue
        data = path.read_bytes()
        if old in data:
            path.write_bytes(data.replace(old, new))
  '';
in
  pkgs.runCommand package.name {
    nativeBuildInputs = [pkgs.makeWrapper];
  } ''
    cp -r ${package} $out
    chmod -R u+w $out

    printf '\n' >> ${certPath}
    cat ${caFile} >> ${certPath}

    ${pkgs.python3}/bin/python3 ${patchSelfReferences} ${package} $out $out

    wrapProgram $out/bin/${binName} \
      --set SSL_CERT_FILE ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
      --set GDK_BACKEND x11 \
      --set GTK_THEME Adwaita:dark
  ''
