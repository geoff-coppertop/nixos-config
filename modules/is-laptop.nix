# Declares the one flag that gates AC-power-sensitive maintenance jobs.
# Read by modules/backups.nix and the nixos-upgrade unit in
# profiles/common/base.nix — it belongs to neither individually.
{lib, ...}: {
  options.custom.isLaptop = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Whether this host runs on battery and should gate AC-power-sensitive maintenance jobs (backups, upgrades).";
  };
}
