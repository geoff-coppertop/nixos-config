# Home Assistant automation for defiant: lock the doors at night.
#
# Locks both door locks at 21:00 Home Assistant local time
# (America/Edmonton) every day. Lock-only — nothing here ever unlocks; a single
# time trigger fires once at 21:00 regardless of the current lock state.
#
# The locks are Aqara U100 locks bridged into Home Assistant through an Aqara M2
# hub over Matter (the Matter server is enabled via custom.matter, and "matter"
# is listed in the HA extraComponents — both in hosts/defiant/configuration.nix).
# Home Assistant exposes each U100 as a lock.* entity; the locking service is
# lock.lock.
#
# The two locks are lock.front_door and lock.garage_door — the entity IDs Home
# Assistant assigned to the U100s bridged through the commissioned M2 hub.
#
# Declared under the "automation manual" key (not bare "automation") so these
# coexist with any UI-created automations, matching
# services.home-assistant.configWritable = true. NixOS merges this list with the
# "automation manual" lists in the sibling files under this directory (see
# default.nix).
{
  services.home-assistant.config."automation manual" = [
    {
      id = "lock_doors_at_night";
      alias = "Lock the doors at 9 PM";
      description = "Lock both door locks every night at 21:00 local time.";
      mode = "single";
      trigger = [
        {
          platform = "time";
          at = "21:00:00";
        }
      ];
      action = [
        {
          service = "lock.lock";
          target.entity_id = [
            "lock.front_door"
            "lock.garage_door"
          ];
        }
      ];
    }
  ];
}
