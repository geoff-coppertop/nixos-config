# Declarative Lovelace dashboard, named "Climate" at the sidebar/view level
# — but the ecobee-specific card inside it is titled "Thermostats", not
# "Climate", since this dashboard grew beyond just the HVAC automations
# (weather and indoor/outdoor air quality cards) and a card called "Climate"
# would be ambiguous next to a weather card.
#
# services.home-assistant.lovelaceConfig switches this dashboard into YAML
# mode, sourced from this Nix attrset instead of HA's own storage — verified
# against the nixpkgs home-assistant module source that this ADDS a new
# dashboard (named "nixos-lovelace" internally) alongside whatever
# UI-editable ones already exist; it doesn't replace or disable the default
# "Overview" dashboard. Given its own title below so it doesn't show up in
# the sidebar as a second, confusingly-identical "Overview".
#
# timer entity rows render their own live countdown client-side from the
# entity's finishes_at attribute — no template sensor or polling needed to
# get that "time remaining" display.
#
# Confirmed live: overriding just dashboards.nixos-lovelace.title (leaving
# mode/filename/icon/show_in_sidebar to the module's own computed default)
# broke HA startup entirely — "required key 'filename' not provided",
# "required key 'mode' not provided". This option's type is a freeform
# attrset (services.home-assistant's settingsFormat), not a submodule with
# per-field mkOptions, so NixOS doesn't merge a partial definition against
# the module's default — providing any definition here discards that
# default's other fields wholesale. The whole attrset has to be spelled out
# every time, matching the module's own default values (mode, filename,
# icon, show_in_sidebar) and overriding only title.
{
  services.home-assistant = {
    config.lovelace.dashboards.nixos-lovelace = {
      mode = "yaml";
      filename = "ui-lovelace.yaml";
      title = "Climate";
      icon = "mdi:thermostat";
      show_in_sidebar = true;
    };

    lovelaceConfig = {
      title = "Climate";
      views = [
        {
          title = "Climate";
          path = "climate";
          icon = "mdi:thermostat";
          cards = [
            {
              type = "entities";
              title = "Thermostats";
              entities = [
                {
                  entity = "input_boolean.climate_summer_mode";
                  name = "Season (on = summer, off = winter)";
                }
                {
                  type = "section";
                  label = "Manual override";
                }
                {
                  entity = "timer.climate_override_main_and_basement";
                  name = "Main/basement";
                }
                {
                  entity = "timer.climate_override_upstairs";
                  name = "Upstairs";
                }
                {
                  type = "section";
                  label = "Devices";
                }
                {
                  entity = "climate.main_and_basement";
                  name = "Main/basement";
                }
                {
                  entity = "climate.upstairs";
                  name = "Upstairs";
                }
              ];
            }
            {
              type = "weather-forecast";
              entity = "weather.forecast_home";
              name = "Weather";
            }
            {
              type = "entities";
              title = "Air Quality";
              entities = [
                {
                  type = "section";
                  label = "Indoor";
                }
                # Read from the ecobees' own SmartSensors, not the
                # thermostats' climate entities — each physically-placed
                # sensor reports air quality independently, so this lists
                # rooms rather than the two HVAC zones above.
                {
                  entity = "sensor.dining_room_air_quality";
                  name = "Dining room";
                }
                {
                  entity = "sensor.master_bedroom_air_quality";
                  name = "Master bedroom";
                }
                {
                  entity = "sensor.upstairs_living_room_air_quality";
                  name = "Upstairs living room";
                }
                {
                  entity = "sensor.basement_living_room_air_quality";
                  name = "Basement living room";
                }
                {
                  entity = "sensor.geoff_s_office_air_quality";
                  name = "Geoff's office";
                }
                {
                  type = "section";
                  label = "Outdoor";
                }
                # outdoor-aqi.nix's REST sensor — AQICN directly, not HA's
                # config_flow-only "waqi" integration (see that file).
                {
                  entity = "sensor.outdoor_aqi";
                  name = "AQI";
                }
              ];
            }
          ];
        }
      ];
    };
  };
}
