# Home Assistant automation for reliant: outside lights on arrival/departure.
#
# Turns the outside lights on when someone is likely leaving or arriving from
# work/school, but only while the sun is below the horizon (dark enough to need
# them), and back off otherwise.
#
# Single desired-state automation: on every relevant edge — the window
# boundaries, sunset/sunrise, and Home Assistant startup — it re-derives what
# the lights *should* be (on iff dark AND inside a window) and sets them. This
# is restart-resilient: if HA reboots or reloads mid-window while it's dark, the
# `homeassistant` start trigger re-evaluates and restores the lights, rather
# than waiting for the next edge (which edge-triggered on/off automations would
# miss). Stating the window logic once, with turn-off as the default branch,
# also removes any chance of a separate on/off automation fighting.
#
# Manual interactions (the HomeKit app, a physical switch, the HA dashboard)
# are respected for a hold-off period: a companion automation records the time
# of any non-automation change that actually disagrees with what the schedule
# would have set, and the scheduling automation skips its run entirely while
# inside that window, leaving the lights exactly as the person left them. A
# manual change that happens to match the schedule's own desired state doesn't
# start a hold-off — there's nothing to protect it from. See
# manualOverrideHoldOffHours below.
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
# switch.patio_lights. Copied from hosts/defiant/home-assistant/outside-lights.nix
# (defiant has since been decommissioned) — re-verify these entity IDs against
# the running instance on this host once activated.
let
  # How long a manual change sticks before the schedule is allowed to override
  # it again. Single source of truth, interpolated into the capture automation
  # below.
  manualOverrideHoldOffHours = 2;
  manualOverrideHelper = "input_datetime.outside_lights_manual_override_until";

  # Single source of truth for the two windows, shared between the schedule's
  # own trigger/condition entries and the capture automation's "would the
  # schedule have set this anyway" check below, so the two can't drift apart.
  morningWindow = {
    start = "06:00:00";
    end = "08:00:00";
  };
  eveningWindow = {
    start = "16:00:00";
    end = "22:00:00";
  };
in {
  services.home-assistant.config = {
    input_datetime.outside_lights_manual_override_until = {
      name = "Outside lights manual override until";
      has_date = true;
      has_time = true;
    };

    "automation manual" = [
      {
        id = "outside_lights_arrival_departure";
        alias = "Outside lights for arrival/departure (when dark)";
        description = "Keep the outside lights on during the morning departure and evening arrival windows while the sun is below the horizon, and off otherwise. Re-evaluated on each window boundary, at sunset/sunrise, and on Home Assistant startup. Skips its run entirely during a manual-override hold-off (see the companion automation below).";
        mode = "single";
        trigger = [
          # Morning departure window boundaries.
          {
            platform = "time";
            at = morningWindow.start;
          }
          {
            platform = "time";
            at = morningWindow.end;
          }
          # Evening arrival window boundaries.
          {
            platform = "time";
            at = eveningWindow.start;
          }
          {
            platform = "time";
            at = eveningWindow.end;
          }
          # Sun crossing the horizon inside a window (e.g. still light at 16:00
          # and darkening later, or dark at 06:00 and brightening at sunrise).
          {
            platform = "sun";
            event = "sunset";
          }
          {
            platform = "sun";
            event = "sunrise";
          }
          # Restore the correct state after a reboot or config reload.
          {
            platform = "homeassistant";
            event = "start";
          }
        ];
        condition = [
          # Skip this run entirely while a manual change is still within its
          # hold-off window. Unknown (never set, e.g. first boot) counts as "no
          # override in effect".
          {
            condition = "template";
            value_template = ''
              {{ is_state('${manualOverrideHelper}', 'unknown')
                 or as_timestamp(now()) >= as_timestamp(states('${manualOverrideHelper}')) }}
            '';
          }
        ];
        action = [
          {
            choose = [
              {
                # Dark, and inside one of the two windows -> lights on.
                conditions = [
                  {
                    condition = "state";
                    entity_id = "sun.sun";
                    state = "below_horizon";
                  }
                  {
                    condition = "or";
                    conditions = [
                      {
                        condition = "time";
                        after = morningWindow.start;
                        before = morningWindow.end;
                      }
                      {
                        condition = "time";
                        after = eveningWindow.start;
                        before = eveningWindow.end;
                      }
                    ];
                  }
                ];
                sequence = [
                  {
                    service = "switch.turn_on";
                    target.entity_id = [
                      "switch.front_entry_lights"
                      "switch.patio_lights"
                    ];
                  }
                ];
              }
            ];
            # Light out, or outside every window -> lights off.
            default = [
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

      {
        id = "outside_lights_manual_override_capture";
        alias = "Outside lights manual override capture";
        description = "Records a non-automation change to the outside lights that disagrees with what the schedule would have set, so the arrival/departure automation holds off for ${toString manualOverrideHoldOffHours}h before touching them again.";
        mode = "single";
        trigger = [
          {
            platform = "state";
            entity_id = [
              "switch.front_entry_lights"
              "switch.patio_lights"
            ];
          }
        ];
        condition = [
          # Only for changes the arrival/departure automation didn't cause
          # itself: its switch.turn_on/turn_off calls run inside that
          # automation's own run, so the resulting state_changed event's
          # context has parent_id set to that run's context id. A manual
          # toggle (HomeKit app, physical switch, HA dashboard) starts a fresh
          # root context, so parent_id is unset — that's what we're watching
          # for here.
          {
            condition = "template";
            value_template = "{{ trigger.to_state.context.parent_id is none }}";
          }
          # Only if the manual change actually disagrees with what the
          # schedule would have set right now — mirrors the "on" branch of the
          # schedule's own choose above. If someone manually sets the lights to
          # the state the schedule already wants, there's nothing to protect
          # from being overridden, so don't start a hold-off.
          {
            condition = "template";
            value_template = ''
              {% set schedule_wants_on = is_state('sun.sun', 'below_horizon') and (
                (now().strftime('%H:%M:%S') >= '${morningWindow.start}' and now().strftime('%H:%M:%S') < '${morningWindow.end}')
                or (now().strftime('%H:%M:%S') >= '${eveningWindow.start}' and now().strftime('%H:%M:%S') < '${eveningWindow.end}')
              ) %}
              {{ trigger.to_state.state != ('on' if schedule_wants_on else 'off') }}
            '';
          }
        ];
        action = [
          {
            service = "input_datetime.set_datetime";
            target.entity_id = manualOverrideHelper;
            data.timestamp = "{{ (as_timestamp(now()) + ${toString (manualOverrideHoldOffHours * 3600)}) | int }}";
          }
        ];
      }
    ];
  };
}
