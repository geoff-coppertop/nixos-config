{pkgs, ...}: {
  home.packages = [
    # The configurator runs flasher.pyz via a bare `python`.
    (pkgs.expresslrs-configurator.overrideAttrs (old: {
      postFixup =
        (old.postFixup or "")
        + ''
          wrapProgram $out/bin/expresslrs-configurator --prefix PATH : ${pkgs.python3}/bin
        '';
    }))
  ];
}
