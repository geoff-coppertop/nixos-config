# Home Assistant automation for reliant: warn when the garage door has been
# left open too long. Notification only — this never closes anything, unlike
# door-locks.nix's lock-only sweep for the doors.
#
# Two known gaps, both called out again inline where they bite:
#
# 1. The door sensor is a real, owned physical Zigbee/Z-Wave contact sensor
#    that is NOT YET PAIRED into Home Assistant/Zigbee2MQTT/Z-Wave JS, so no
#    entity_id exists yet. `garageDoorContact` below is a clearly-fake
#    placeholder ("PLACEHOLDER_" prefix) standing in for it — replace it with
#    the real entity_id once paired (see hosts/reliant/README.md § Device
#    Pairing Notes for the pairing steps), then verify with
#    `python3 tools/check_ha_entities.py reliant`. Until then this automation
#    loads cleanly but can never fire, same as any other wrong/missing entity
#    ID in this repo.
# 2. There is no `notify.mobile_app_*` service configured anywhere in this
#    repo yet, and this file doesn't know one to call. It uses
#    `persistent_notification.create` (built into HA core, shows under the
#    bell icon in the HA UI/app, no companion-app service name required) as a
#    placeholder action. Replace/augment `notifyAction` below with a real
#    `notify.mobile_app_<device>` call once that service name is known
#    (Settings > Devices & Services > Mobile App, or Developer Tools >
#    Actions searching "notify") if a push notification is wanted instead of
#    or alongside the persistent notification.
#
# This is explicitly NOT the ratgdo32 ESPHome controller's own door-position
# sensing (a separate, in-progress feature on another branch) — this is an
# independent, physically separate contact sensor on the door itself, so the
# alert still works even if the ratgdo32 firmware/integration is down.
#
# Design: one periodic sweep automation, not two bolted-together ones.
#
# The door sensor is expected to be a Zigbee2MQTT-bridged contact sensor
# (device_class "door": "on" = open, "off" = closed) — the same pattern
# presence-lighting.nix already uses for the Utility Room's Parasoll contact
# sensor (binary_sensor.utility_room_parasoll_contact). If the actual device
# paired turns out to be Z-Wave instead, only the entity_id and its backing
# integration change; the "on" = open / "off" = closed contract and
# everything below is identical either way.
#
# "Everyone away" reuses the same zone.home person-count pattern already used
# throughout ecobee-climate.nix: `numeric_state` on `zone.home`, `below: 1`
# meaning nobody home.
#
# The two requirements — a longer away-only threshold, and a shorter
# overnight threshold regardless of presence — are NOT two separate
# automations. A periodic sweep (time_pattern, same shape as
# door-locks.nix's overnight lock sweep) checks, every awaySweepMinutes, how
# long the door has been continuously open
# (`now() - states(garageDoorContact).last_changed`, same technique
# door-locks.nix uses for its lock hold-off) against whichever threshold
# currently applies:
#
# - Overnight (21:00-06:00, the same window door-locks.nix uses) is checked
#   FIRST and does not require anyone to be away: a garage door open at 2am
#   is worth flagging even with people home and asleep upstairs, since
#   nobody's actively watching it. Its threshold (overnightOpenThreshold,
#   10 minutes) is short — this is the higher-security window.
# - Away (zone.home below 1) is checked second, any time of day, with a
#   longer threshold (awayOpenThreshold, 20 minutes) — long enough that
#   loading the car right after everyone leaves doesn't immediately alert,
#   short enough to still catch a door genuinely forgotten open.
#
# A single choose block with the overnight branch first naturally gives
# overnight priority when both conditions hold (away AND overnight) without
# needing to special-case that overlap — whichever branch's condition and
# threshold are satisfied first just fires.
#
# One-shot per opening, not a repeat every sweep: `notifiedHelper`
# (input_boolean) is set true the first time either branch fires, and gates
# both branches from firing again, so a door left open for hours gets one
# notification, not one every awaySweepMinutes. A `door_closed` trigger (the
# contact sensor going back to "off") clears the flag and dismisses the
# persistent notification, so the next time the door is left open again
# starts a fresh alert cycle. This dispatches on *which trigger fired* (via
# each trigger's `id`), the same reason presence-lighting.nix does: if the
# door_closed branch instead re-checked "is the door currently open" the way
# the sweep branches do, it just evaluated to false and matched nothing
# useful — but re-deriving intent from current state on every trigger type
# here would also mean the sweep and the close-reset could race handling the
# same event inconsistently, so dispatching on trigger id keeps each edge's
# handling unambiguous, matching the established pattern in this directory.
#
# Declared under the "automation manual" key (not bare "automation") so these
# coexist with any UI-created automations, matching
# services.home-assistant.configWritable = true. NixOS merges this list with
# the "automation manual" lists in the sibling files under this directory
# (see default.nix).
let
  # PLACEHOLDER — this sensor is not yet paired; there is no real entity_id
  # yet. Replace with the real one once paired and verified against the
  # running instance (see the file header and hosts/reliant/README.md §
  # Device Pairing Notes). Deliberately not a plausible-looking guess.
  garageDoorContact = "binary_sensor.PLACEHOLDER_garage_door_contact";

  notifiedHelper = "input_boolean.garage_door_open_alert_notified";
  notificationId = "garage_door_open_alert";

  # How often the sweep runs. Finer than the shorter (overnight) threshold's
  # own /10 door-locks.nix precedent, since a 10-minute sweep against a
  # 10-minute threshold could delay detection by up to another 10 minutes.
  awaySweepMinutes = "/5";

  overnightOpenThresholdSeconds = 600; # 10 minutes
  awayOpenThresholdSeconds = 1200; # 20 minutes

  overnightCondition = {
    condition = "time";
    after = "21:00:00";
    before = "06:00:00";
  };

  awayCondition = {
    condition = "numeric_state";
    entity_id = "zone.home";
    below = 1;
  };

  doorOpenLongerThan = thresholdSeconds: {
    condition = "template";
    value_template = ''
      {{ is_state('${garageDoorContact}', 'on') and (now() - states['${garageDoorContact}'].last_changed).total_seconds() >= ${toString thresholdSeconds} }}
    '';
  };

  notNotified = {
    condition = "state";
    entity_id = notifiedHelper;
    state = "off";
  };

  # Placeholder action — see the file header, item 2, for why this isn't a
  # notify.mobile_app_* call. `notification_id` is fixed so a repeat alert
  # (door closed, then left open again later) updates the same notification
  # rather than piling up a new one every time.
  notifyAction = {
    service = "persistent_notification.create";
    data = {
      notification_id = notificationId;
      title = "Garage door left open";
      message = "The garage door has been open for a while and hasn't been closed. Check it.";
    };
  };
in {
  services.home-assistant.config = {
    input_boolean.garage_door_open_alert_notified = {
      name = "Garage Door: open alert notified";
      icon = "mdi:garage-alert";
    };

    "automation manual" = [
      {
        id = "garage_door_open_alert";
        alias = "Garage Door: left open alert";
        description = "Warns (notification only, never auto-closes) when the garage door has been continuously open for ${toString (overnightOpenThresholdSeconds / 60)} minutes during the 21:00-06:00 overnight window, or for ${toString (awayOpenThresholdSeconds / 60)} minutes any time everyone is away. One notification per opening; resets when the door closes.";
        mode = "single";
        trigger = [
          {
            id = "sweep";
            platform = "time_pattern";
            minutes = awaySweepMinutes;
          }
          {
            id = "door_closed";
            platform = "state";
            entity_id = garageDoorContact;
            to = "off";
          }
          # Catch a door already open past a threshold at the moment HA
          # (re)starts, same reasoning as the startup triggers elsewhere in
          # this directory, rather than waiting up to awaySweepMinutes.
          {
            id = "startup";
            platform = "homeassistant";
            event = "start";
          }
        ];
        action = [
          {
            choose = [
              {
                # Door just closed -> reset for the next opening.
                conditions = [
                  {
                    condition = "trigger";
                    id = ["door_closed"];
                  }
                ];
                sequence = [
                  {
                    service = "input_boolean.turn_off";
                    target.entity_id = notifiedHelper;
                  }
                  {
                    service = "persistent_notification.dismiss";
                    data.notification_id = notificationId;
                  }
                ];
              }
              {
                # Overnight, open past the (shorter) overnight threshold, not
                # already notified -> alert. Checked before the away branch
                # so overnight takes priority on the away+overnight overlap.
                conditions = [
                  overnightCondition
                  (doorOpenLongerThan overnightOpenThresholdSeconds)
                  notNotified
                ];
                sequence = [
                  notifyAction
                  {
                    service = "input_boolean.turn_on";
                    target.entity_id = notifiedHelper;
                  }
                ];
              }
              {
                # Everyone away, open past the (longer) away threshold, not
                # already notified -> alert, any time of day.
                conditions = [
                  awayCondition
                  (doorOpenLongerThan awayOpenThresholdSeconds)
                  notNotified
                ];
                sequence = [
                  notifyAction
                  {
                    service = "input_boolean.turn_on";
                    target.entity_id = notifiedHelper;
                  }
                ];
              }
            ];
            # Door closed already, or open but neither threshold/condition
            # met yet, or already notified -> nothing to do this sweep.
            default = [];
          }
        ];
      }
    ];
  };
}
