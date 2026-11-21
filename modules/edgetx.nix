{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf;
  localFile = import ../lib/local-file.nix;
in {
  options.custom.edgetx.enable = mkEnableOption "EdgeTX radio flashing: STM32 DFU and radio/ELRS USB-serial access, dfu-util, ExpressLRS Configurator";

  config = mkIf config.custom.edgetx.enable {
    environment.systemPackages = [pkgs.dfu-util pkgs.expresslrs-configurator];

    # packages, not extraRules: see docs/workstation.md#why-servicesudevpackages-and-not-extrarules
    services.udev.packages = [
      (pkgs.runCommand "edgetx-udev-rules" {} ''
        mkdir -p $out/etc/udev/rules.d
        cp ${localFile {path = ./udev-rules/69-edgetx.rules;}} $out/etc/udev/rules.d/69-edgetx.rules
      '')
    ];
  };
}
