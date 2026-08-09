# Home Assistant automation for reliant: outside lights on arrival/departure.
#
# Turns the outside lights on when someone is likely leaving or arriving from
# work/school, but only while the sun is below the horizon (dark enough to need
# them); a companion automation turns them back off.
#
# The outside lights are HomeKit switches, exposed by Home Assistant as
# `switch.*` entities via the HomeKit Controller integration (enabled in
# modules/home-assistant.nix), so these use the switch.turn_on / switch.turn_off
# services.
#
# Declared under the `automation manual` key (not bare `automation`) so these
# coexist with any UI-created automations, which land in automations.yaml —
# matching services.home-assistant.configWritable = true.
#
# The two outside-light switches: switch.front_entry_lights and
# switch.patio_lights. Copied from
# hosts/defiant/home-assistant/outside-lights.nix — re-verify these entity IDs
# against the running instance on this host once activated.
{
  services.home-assistant.config."automation manual" = [
    {
      id = "outside_lights_arrival_departure_on";
      alias = "Outside lights on for arrival/departure (when dark)";
      description = "Turn on the outside lights during the morning departure and evening arrival windows, but only while the sun is below the horizon.";
      mode = "single";
      trigger = [
        # Start of the morning departure window.
        {
          platform = "time";
          at = "06:00:00";
        }
        # Start of the evening arrival window.
        {
          platform = "time";
          at = "16:00:00";
        }
        # Sun drops below the horizon while we're already inside a window
        # (covers evenings that are still light at 16:00 and darken later).
        {
          platform = "sun";
          event = "sunset";
        }
      ];
      condition = [
        # Only when it's dark.
        {
          condition = "state";
          entity_id = "sun.sun";
          state = "below_horizon";
        }
        # Only inside one of the two windows.
        {
          condition = "or";
          conditions = [
            {
              condition = "time";
              after = "06:00:00";
              before = "08:00:00";
            }
            {
              condition = "time";
              after = "16:00:00";
              before = "22:00:00";
            }
          ];
        }
      ];
      action = [
        {
          service = "switch.turn_on";
          target.entity_id = [
            "switch.front_entry_lights"
            "switch.patio_lights"
          ];
        }
      ];
    }
    {
      id = "outside_lights_arrival_departure_off";
      alias = "Outside lights off after arrival/departure windows";
      description = "Turn the outside lights back off at the end of each window, or as soon as the sun comes up if they were left on into daylight.";
      mode = "single";
      trigger = [
        # End of the morning departure window.
        {
          platform = "time";
          at = "08:00:00";
        }
        # End of the evening arrival window (bedtime).
        {
          platform = "time";
          at = "22:00:00";
        }
        # Sun comes up while lights are still on (dark at 06:00, sunrise 07:00).
        {
          platform = "sun";
          event = "sunrise";
        }
      ];
      action = [
        {
          service = "switch.turn_off";
          target.entity_id = [
            "switch.front_entry_lights"
            "switch.patio_lights"
          ];
        }
      ];
    }
  ];
}
