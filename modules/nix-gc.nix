# Declares the retention count the nix-gc preStart in profiles/common/base.nix
# prunes profiles down to. It is host-tunable because storage headroom is a
# property of the machine, not of garbage collection: defiant boots from a 30G
# SD card where ten system generations leave no room for a new closure, while
# the NVMe/SSD hosts have space to spare.
{lib, ...}: {
  options.custom.nix.gc.keepGenerations = lib.mkOption {
    type = lib.types.ints.positive;
    default = 10;
    example = 3;
    description = "How many generations of the system profile and of each home-manager profile the weekly nix-gc run keeps. Pruning by count happens before nix-gc prunes by age, so a generation is dropped if it is beyond this count OR older than 30 days. Lower this on hosts with little disk headroom.";
  };
}
