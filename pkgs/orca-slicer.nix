# See docs/desktop.md § OrcaSlicer. Trusted CAs live in a single concatenated
# PEM file at $out/share/OrcaSlicer/cert/printer.cer (confirmed by direct
# inspection: five existing blocks) — this appends a sixth via lib/trust-printer-ca.nix.
{pkgs}: let
  localFile = import ../lib/local-file.nix;
  trustPrinterCa = import ../lib/trust-printer-ca.nix;
  bambuddyCa = localFile {path = ./bambuddy-virtual-printer-ca.pem;};
in
  trustPrinterCa {
    inherit pkgs;
    package = pkgs.orca-slicer;
    certPath = "$out/share/OrcaSlicer/cert/printer.cer";
    caFile = bambuddyCa;
    binName = "orca-slicer";
  }
