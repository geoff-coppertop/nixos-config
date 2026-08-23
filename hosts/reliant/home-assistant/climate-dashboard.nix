# The single declarative Lovelace dashboard for reliant, sidebar-titled
# "Home". Confirmed against the nixpkgs home-assistant module source
# (nixos/modules/services/home-automation/home-assistant.nix, pinned rev in
# flake.lock): lovelaceConfig/lovelaceConfigFile can only ever generate
# content for ONE dashboard file (ui-lovelace.yaml) — the module has no
# mechanism to declare card/view content for a second, independently-titled
# sidebar dashboard. So unrelated concerns that each want their own page
# become separate *views* (tabs) inside this one file/dashboard, not
# separate files each owning their own dashboard — "Climate" and "Bedtime"
# below, and wherever this grows next. Kept generically titled "Home" (not
# "Climate") for exactly that reason: it stopped being just a climate
# dashboard once the ecobee-specific card was joined by weather/air-quality
# cards, and now a second, unrelated view (Bedtime).
#
# The ecobee-specific card inside the Climate view is itself titled
# "Thermostats", not "Climate" — a card called "Climate" would be ambiguous
# next to a weather card in the same view.
#
# services.home-assistant.lovelaceConfig switches this dashboard into YAML
# mode, sourced from this Nix attrset instead of HA's own storage — verified
# against the nixpkgs home-assistant module source that this ADDS a new
# dashboard (named "nixos-lovelace" internally) alongside whatever
# UI-editable ones already exist; it doesn't replace or disable the default
# "Overview" dashboard. Given its own title below so it doesn't show up in
# the sidebar as a second, confusingly-identical "Overview".
#
# The Bedtime view's cards read hosts/reliant/home-assistant/kids-wake-lights.nix's
# per-room input_boolean/input_datetime helpers directly (not the light
# entities themselves) — the point of this view is adjusting the schedule,
# which is exactly what those helpers are for; the automations already do
# the actual light control.
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
      title = "Home";
      icon = "mdi:home";
      show_in_sidebar = true;
    };

    lovelaceConfig = {
      title = "Home";
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
              type = "entities";
              title = "Set Points";
              # input_number.climate_*_* from ecobee-climate.nix — the
              # schedule reads these live, so a slider tweak here applies
              # on its next trigger (including immediately, since these
              # entities are themselves triggers) rather than needing a
              # redeploy. Winter and summer are stored as fully separate
              # Day/Night/Away triples per zone, not a shared value with a
              # separate "away" — that's what lets switching seasons keep
              # both sets of tuning instead of losing one, per
              # ecobee-climate.nix's mkHeatOnlyZone. Only the current
              # season's rows are actually visible per zone — each row is
              # wrapped in a `conditional` row keyed off
              # input_boolean.climate_summer_mode, rather than showing both
              # seasons at once, so flipping the toggle swaps which set of
              # sliders is on screen instead of leaving every value visible
              # with no indication which are live right now. Upstairs'
              # summer rows are pairs (heat floor/cool ceiling), not single
              # targets — it's the only zone with real cooling, so its
              # heat_cool dual setpoint needs both ends shown.
              entities = let
                periodName = period:
                  if period == "day"
                  then "Day (home)"
                  else if period == "night"
                  then "Night (home)"
                  else "Away";
                mkRow = zone: season: period: {
                  entity = "input_number.climate_${zone}_${season}_${period}";
                  name = periodName period;
                };
                mkDualRow = zone: season: period: end: {
                  entity = "input_number.climate_${zone}_${season}_${period}_${end}";
                  name = "${periodName period} — ${
                    if end == "low"
                    then "heat floor"
                    else "cool ceiling"
                  }";
                };
                mkConditionalRow = seasonState: row: {
                  type = "conditional";
                  conditions = [
                    {
                      entity = "input_boolean.climate_summer_mode";
                      state = seasonState;
                    }
                  ];
                  inherit row;
                };
                mkWinterRow = mkConditionalRow "off";
                mkSummerRow = mkConditionalRow "on";
                mkZoneRows = zone:
                  (map (period: mkWinterRow (mkRow zone "winter" period)) ["day" "night" "away"])
                  ++ (map (period: mkSummerRow (mkRow zone "summer" period)) ["day" "night" "away"]);
                upstairsSummerRows =
                  builtins.concatMap
                  (period: [
                    (mkSummerRow (mkDualRow "upstairs" "summer" period "low"))
                    (mkSummerRow (mkDualRow "upstairs" "summer" period "high"))
                  ])
                  ["day" "night" "away"];
              in
                [
                  {
                    type = "section";
                    label = "Main/basement";
                  }
                ]
                ++ (mkZoneRows "main_and_basement")
                ++ [
                  {
                    type = "section";
                    label = "Upstairs";
                  }
                ]
                ++ (map (period: mkWinterRow (mkRow "upstairs" "winter" period)) ["day" "night" "away"])
                ++ upstairsSummerRows;
            }
            {
              type = "history-graph";
              title = "Temperature History";
              hours_to_show = 24;
              entities = [
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
        {
          title = "Bedtime";
          path = "bedtime";
          icon = "mdi:weather-night";
          cards = [
            {
              type = "entities";
              title = "Abigail's Room";
              entities = [
                {
                  entity = "input_boolean.abigail_wake_lights_enabled";
                  name = "Wake lights enabled";
                }
                {
                  entity = "input_datetime.abigail_bedtime";
                  name = "Bedtime";
                }
                {
                  entity = "input_datetime.abigail_wake_weekday";
                  name = "Wake time (weekday)";
                }
                {
                  entity = "input_datetime.abigail_wake_weekend";
                  name = "Wake time (weekend)";
                }
              ];
            }
            {
              type = "entities";
              title = "Evelyn's Room";
              entities = [
                {
                  entity = "input_boolean.evelyn_wake_lights_enabled";
                  name = "Wake lights enabled";
                }
                {
                  entity = "input_datetime.evelyn_bedtime";
                  name = "Bedtime";
                }
                {
                  entity = "input_datetime.evelyn_wake_weekday";
                  name = "Wake time (weekday)";
                }
                {
                  entity = "input_datetime.evelyn_wake_weekend";
                  name = "Wake time (weekend)";
                }
              ];
            }
          ];
        }
      ];
    };
  };
}
