# See docs/desktop.md § OrcaSlicer. Trusted CAs live in a single concatenated
# PEM file at $out/share/OrcaSlicer/cert/printer.cer (confirmed by direct
# inspection: five existing blocks) — this appends a sixth.
{pkgs}: let
  localFile = import ../lib/local-file.nix;
  bambuddyCa = localFile {path = ./bambuddy-virtual-printer-ca.pem;};
in
  pkgs.orca-slicer.overrideAttrs (old: {
    # printer.cer ships read-only (0444) and with no trailing newline, so
    # this needs u+w and its own leading newline before appending.
    postInstall =
      (old.postInstall or "")
      + ''
        chmod u+w $out/share/OrcaSlicer/cert/printer.cer
        printf '\n' >> $out/share/OrcaSlicer/cert/printer.cer
        cat ${bambuddyCa} >> $out/share/OrcaSlicer/cert/printer.cer
      '';
  })
