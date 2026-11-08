{pkgs, ...}: {
  home.packages = [
    # Upstream shells out to a bare `python` for flasher.pyz; see
    # docs/desktop.md § Known Gotchas.
    (pkgs.expresslrs-configurator.overrideAttrs (old: {
      postFixup =
        (old.postFixup or "")
        + ''
          wrapProgram $out/bin/expresslrs-configurator --prefix PATH : ${pkgs.python3}/bin
        '';
    }))
  ];
}
