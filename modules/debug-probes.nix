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
    # services.udev.packages (not extraRules) so this file keeps its own
    # "69-" name in /etc/udev/rules.d/ instead of merging into a generated
    # 99-local.rules. Ordering matters: this file's TAG+="uaccess"
    # assignment must be read *before* systemd's own 73-seat-late.rules
    # checks TAG=="uaccess" to decide whether to queue the uaccess builtin.
    # extraRules sorts everything into 99-local.rules (after 73), silently
    # dropping the ACL grant on every first-ever device enumeration — a
    # device re-triggered later picks up the tag persisted from that first
    # pass, which is why it can look intermittent rather than reliably broken.
    services.udev.packages = [
      (pkgs.runCommand "probe-rs-udev-rules" {} ''
        mkdir -p $out/etc/udev/rules.d
        cp ${localFile {path = ./udev-rules/69-probe-rs.rules;}} $out/etc/udev/rules.d/69-probe-rs.rules
      '')
    ];

    # The rules set GROUP="plugdev" as a fallback alongside TAG+="uaccess";
    # NixOS doesn't create this group by default.
    users.groups.plugdev = {};
  };
}
