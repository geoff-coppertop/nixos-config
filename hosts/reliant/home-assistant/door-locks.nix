# Home Assistant automation for reliant: keep the doors locked overnight.
#
# Every 10 minutes during the overnight window (21:00–06:00 local time) this
# locks any door that is currently unlocked AND has been untouched past the
# hold-off (holdOffSeconds below, 10 min). Because each manual lock/unlock
# refreshes the entity's last_changed, the hold-off is measured from the last
# manual interaction: active in-and-out use keeps deferring the re-lock, and a
# door is locked on the first sweep once activity stops. Lock-only — this never
# unlocks anything. The result is that the doors always end up locked overnight
# while backing off during active use.
#
# The locks are Aqara U100 locks bridged into Home Assistant through an Aqara M2
# hub over Matter (custom.matter enables the Matter server and "matter" is in the
# HA extraComponents — both in hosts/reliant/configuration.nix). HA exposes each
# U100 as a lock.* entity; the locking service is lock.lock. The hold-off's
# reaction to *manual* use depends on the U100 reporting physical operations
# (thumb-turn/keypad/key) back over the Matter bridge; if it does not, the sweep
# still re-locks the door on its next pass, so overnight-locked still holds — the
# only thing lost is the grace period during active use.
#
# The two locks are lock.front_door and lock.garage_door — entity IDs carried
# over from defiant's restored Home Assistant state during the Phase 2
# migration (see docs/smart-home.md § Migration: defiant → reliant).
#
# Declared under the "automation manual" key (not bare "automation") so these
# coexist with any UI-created automations, matching
# services.home-assistant.configWritable = true. NixOS merges this list with the
# "automation manual" lists in the sibling files under this directory (see
# default.nix).
let
  lockEntities = [
    "lock.front_door"
    "lock.garage_door"
  ];
  # How long a door must sit unlocked with no manual interaction before this
  # re-locks it, measured from the entity's last_changed. Interpolated into the
  # template condition below.
  holdOffSeconds = 600;
in {
  services.home-assistant.config."automation manual" = [
    {
      id = "lock_doors_overnight";
      alias = "Keep the doors locked overnight";
      description = "Every 10 minutes between 21:00 and 06:00, lock any door left unlocked and untouched past the hold-off. Lock-only; never unlocks.";
      mode = "single";
      trigger = [
        {
          platform = "time_pattern";
          minutes = "/10";
        }
      ];
      condition = [
        # Overnight window only; after > before spans midnight in HA.
        {
          condition = "time";
          after = "21:00:00";
          before = "06:00:00";
        }
      ];
      action = [
        {
          repeat = {
            for_each = lockEntities;
            sequence = [
              {
                # Lock this door only if it is unlocked and has been untouched
                # (no state change) for at least the hold-off.
                "if" = [
                  {
                    condition = "template";
                    value_template = "{{ is_state(repeat.item, 'unlocked') and (now() - states[repeat.item].last_changed).total_seconds() >= ${toString holdOffSeconds} }}";
                  }
                ];
                "then" = [
                  {
                    service = "lock.lock";
                    target.entity_id = "{{ repeat.item }}";
                  }
                ];
              }
            ];
          };
        }
      ];
    }
  ];
}
