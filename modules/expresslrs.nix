{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf;
in {
  options.custom.expresslrs.enable = mkEnableOption "udev rules for flashing ExpressLRS hardware over USB (CP210x/CH340 UART bridges, STM32 VCP/DFU, ESP32-S3 native USB)";

  config = mkIf config.custom.expresslrs.enable {
    services.udev.packages = [
      (pkgs.writeTextDir "etc/udev/rules.d/69-expresslrs.rules" ''
        SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", TAG+="uaccess"
        SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="7523", TAG+="uaccess"
        SUBSYSTEM=="tty", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="5740", TAG+="uaccess"
        SUBSYSTEM=="tty", ATTRS{idVendor}=="303a", ATTRS{idProduct}=="1001", TAG+="uaccess"
        SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="df11", TAG+="uaccess"
      '')
    ];
  };
}
