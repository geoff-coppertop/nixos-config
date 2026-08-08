# Best-effort template, not a `nixos-generate-config` scan — this machine
# has not been physically installed yet, so there is no live system to scan.
# Mirrors excelsior's hardware.nix (also a UEFI x86_64 mini PC with a plain
# SATA/mSATA disk): systemd-boot, EFI variable access, redistributable
# firmware, Intel microcode. Verify against the installer's own hardware
# detection during Step 5 (docs/provisioning.md) and correct here if the
# Brix needs anything this omits (e.g. a specific initrd kernel module for
# the mSATA controller) — none is expected, but this has not been confirmed
# on real hardware.
{
  boot = {
    loader = {
      systemd-boot = {
        enable = true;
        # Default is 10 (matches enterprise-d/excelsior). Lowered — see the
        # comment on custom.nix.gc.keepGenerations in configuration.nix: the
        # 120GB mSATA disk is far smaller than either of those hosts', and
        # defiant's SD card already showed what an unbounded generation count
        # does to a small, fixed disk.
        configurationLimit = 5;
      };

      efi.canTouchEfiVariables = true;
    };

    initrd.systemd.enable = true;
  };

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;
}
