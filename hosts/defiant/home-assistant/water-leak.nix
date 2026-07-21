# Home Assistant automation for defiant: close the water main on any leak.
#
# Fires when ANY leak sensor goes wet, closes the water main, and alerts
# everyone. The trigger is written against the moisture device class rather
# than a hardcoded entity list, so every current and future leak sensor is
# covered automatically — adding a sensor requires no change here, as long as
# Home Assistant exposes it as a binary_sensor with device_class "moisture"
# (which the standard Zigbee/Z-Wave/Guardian leak detectors do).
#
# HARDWARE NOT YET INSTALLED. The valve action below targets a placeholder
# entity (valve.water_main). Two things to reconcile once the valve is bought:
#   - Guardian by Elexa (native local HA integration) historically exposes its
#     shutoff as a *switch* entity, where closing the valve is switch.turn_off
#     on that switch — NOT the valve.* domain. If you go Guardian, replace the
#     valve.close_valve action with:
#         service = "switch.turn_off";
#         target.entity_id = "switch.<guardian valve entity>";
#   - A Zooz Titan (Z-Wave) or other valve.* domain device keeps the
#     valve.close_valve form below; just fix the entity_id.
# Confirm the real entity_id in HA (Developer Tools > States) after pairing.
#
# Alerting uses two independent steps so a missing/unconfigured notifier never
# swallows the alarm: persistent_notification.create always fires in the HA UI,
# and notify.notify (continue_on_error) pushes to the Companion app on each
# paired phone. Point notify.notify at a specific notify.mobile_app_<device>
# service if you'd rather target one phone instead of broadcasting to all.
#
# Declared under the "automation manual" key (not bare "automation") so this
# coexists with any UI-created automations — matching
# services.home-assistant.configWritable = true. NixOS merges this list with
# the "automation manual" lists in the sibling files under this directory (see
# default.nix).
{
  services.home-assistant.config."automation manual" = [
    {
      id = "close_water_main_on_leak";
      alias = "Close water main and alert on any leak";
      description = "When any moisture (leak) sensor goes wet, close the water main and notify everyone.";
      mode = "single";

      # A single template trigger that watches every moisture binary_sensor at
      # once: it becomes true the moment the count of wet leak sensors rises
      # above zero, so any current or future leak detector triggers it.
      trigger = [
        {
          platform = "template";
          value_template = ''
            {{ states.binary_sensor
               | selectattr('attributes.device_class', 'eq', 'moisture')
               | selectattr('state', 'eq', 'on')
               | list | count > 0 }}
          '';
        }
      ];

      # Names of the currently-wet sensors, computed once and reused in both
      # notifications so the alert says exactly which detector(s) tripped.
      variables = {
        wet_sensors = ''
          {{ states.binary_sensor
             | selectattr('attributes.device_class', 'eq', 'moisture')
             | selectattr('state', 'eq', 'on')
             | map(attribute='name') | list | join(', ') }}
        '';
      };

      action = [
        # 1. Close the valve first — stopping the water takes priority over
        #    everything else. (Placeholder entity/service — see header note.)
        {
          service = "valve.close_valve";
          target.entity_id = "valve.water_main";
        }
        # 2. Dashboard notification — no external dependency, always fires.
        {
          service = "persistent_notification.create";
          data = {
            title = "Water leak detected";
            message = "Leak detected at: {{ wet_sensors }}. Water main has been closed.";
          };
        }
        # 3. Push to phones via the Companion app. continue_on_error so a
        #    missing notifier can't block the dashboard alert above.
        {
          service = "notify.notify";
          continue_on_error = true;
          data = {
            title = "🚨 Water leak — main closed";
            message = "Leak detected at: {{ wet_sensors }}.";
          };
        }
      ];
    }
  ];
}
