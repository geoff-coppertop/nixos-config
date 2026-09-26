# See docs/desktop.md § Bambu Studio. Same cert-trust fix as
# pkgs/orca-slicer.nix; printer.cer is the same concatenated-PEM format.
{pkgs}: let
  localFile = import ../lib/local-file.nix;
  trustPrinterCa = import ../lib/trust-printer-ca.nix;
  bambuddyCa = localFile {path = ./bambuddy-virtual-printer-ca.pem;};
in
  trustPrinterCa {
    inherit pkgs;
    package = pkgs.bambu-studio;
    certPath = "$out/share/BambuStudio/cert/printer.cer";
    caFile = bambuddyCa;
    binName = "bambu-studio";
  }
