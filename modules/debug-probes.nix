{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf;
  localFile = import ../lib/local-file.nix;
in {
  options.custom.debugProbes.enable = mkEnableOption "udev rules for USB JTAG/SWD debug probes (ST-Link, J-Link, FTDI, CMSIS-DAP incl. Raspberry Pi Debug Probe)";

  config = mkIf config.custom.debugProbes.enable {
    # packages, not extraRules: see docs/workstation.md#why-servicesudevpackages-and-not-extrarules
    services.udev.packages = [
      (pkgs.runCommand "probe-rs-udev-rules" {} ''
        mkdir -p $out/etc/udev/rules.d
        cp ${localFile {path = ./udev-rules/69-probe-rs.rules;}} $out/etc/udev/rules.d/69-probe-rs.rules
      '')
    ];

    users.groups.plugdev = {};
  };
}
