# Home Assistant automation for reliant: warn (never auto-close) when the
# garage door has been left open too long. Separate physical contact sensor,
# not the ratgdo32 controller's own door sensing (another branch) — this
# still works if that integration is down.
#
# One sweep automation, not two bolted together: every awaySweepMinutes it
# checks how long the door's been open (last_changed, same technique as
# door-locks.nix's hold-off) against whichever threshold applies — overnight
# (21:00-06:00, checked first so it wins any overlap) is short because it
# doesn't require anyone away; the away-anytime threshold is longer so
# leaving to load the car doesn't trigger it. `notifiedHelper` latches so a
# long-open door alerts once, not every sweep; a `door_closed` trigger resets
# it and dismisses the notification. Action dispatches on trigger id (as
# presence-lighting.nix does) rather than re-checking current state, since
# the close-reset firing exactly when the door is still "open" in a stale
# read would otherwise race the sweep.
#
# "automation manual" (not bare "automation") to coexist with UI-created
# automations; merged with sibling files' lists via default.nix.
let
  # The paired garage door tilt sensor. Assumes the same "on" = open /
  # "off" = closed contract as every other door/window contact sensor in
  # this repo (presence-lighting.nix's Parasoll sensor) — confirm against
  # the entity's actual state in HA if this ever misfires.
  garageDoorContact = "binary_sensor.garage_door_tilt_sensor_contact";

  notifiedHelper = "input_boolean.garage_door_open_alert_notified";
  notificationId = "garage_door_open_alert";

  # Finer than the overnight threshold itself, so detection isn't delayed by
  # up to a full sweep interval.
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

  # Fixed notification_id so a repeat alert updates rather than piling up.
  # Two actions: the persistent_notification for the HA UI/dashboard, plus a
  # push to every registered mobile_app device. The push targets
  # `integration_entities('mobile_app') | select('match', 'notify\.')` —
  # confirmed against home-assistant/core: `mobile_app`'s notify platform
  # (homeassistant/components/mobile_app/notify.py) now sets up one
  # `NotifyEntity` per device rather than a `notify.mobile_app_<device>`
  # service, sent via the core `notify.send_message` action targeting
  # entities in the `notify` domain (homeassistant/components/notify/
  # services.yaml); `integration_entities` (homeassistant/helpers/template/
  # extensions/config_entries.py) resolves every entity_id belonging to the
  # `mobile_app` domain, filtered here to the `notify.*` ones. Templated
  # rather than a hardcoded device name (or a static `group` notify
  # platform, which also requires hand-listing services) so a phone added or
  # removed later needs no edit here.
  notifyAction = [
    {
      service = "persistent_notification.create";
      data = {
        notification_id = notificationId;
        title = "Garage door left open";
        message = "The garage door has been open for a while and hasn't been closed. Check it.";
      };
    }
    {
      service = "notify.send_message";
      target.entity_id = ''{{ integration_entities('mobile_app') | select('match', 'notify\.') | list }}'';
      data = {
        title = "Garage door left open";
        message = "The garage door has been open for a while and hasn't been closed. Check it.";
      };
    }
  ];
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
                sequence =
                  notifyAction
                  ++ [
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
                sequence =
                  notifyAction
                  ++ [
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
