# Home Assistant automation for reliant: Abigail's and Evelyn's Hue wake/sleep
# lights.
#
# Very dim dark blue at bedtime, switching to bright neutral white for two
# hours after wake time (times out on its own to save power), off the rest
# of the day. One concern covering both rooms, so both live in this file.
#
# Per-room wake times are adjustable from the HA UI (Settings > Devices &
# Services > Helpers) with no Nix/rebuild needed —
# input_datetime.<slug>_bedtime/_wake_weekday/_wake_weekend hold the trigger
# times, and input_boolean.<slug>_wake_lights_enabled is the per-room toggle.
#
# The bulbs are Hue, paired through the "hue" integration (one-time manual
# pairing, not part of this repo). "hue" is in
# custom.home-assistant.extraComponents in hosts/reliant/configuration.nix:
# unlike homekit_controller/matter/sonos it needs no extra entry to be
# *discovered* in the UI, but selecting it without the entry installed fails
# importing its `aiohue` dependency the moment the config flow runs — "hue"
# is not part of HA's default_config baseline. Added defensively per
# docs/smart-home.md § Choosing extraComponents, same reasoning as
# mqtt/zwave_js there.
#
# `lights` below are the real entity IDs, confirmed against reliant's live
# entity registry with `tools/check_ha_entities.py reliant` after the Hue
# bridge was paired. Nothing else here has been run against real hardware yet.
#
# Restart-resilient like presence-lighting.nix and ecobee-climate.nix: a
# `homeassistant` start trigger re-derives which of the three states (sleep /
# wake-bright / off) the current time falls into via a `choose` block, so a
# reboot doesn't leave lights stuck. The sleep window wraps midnight, so the
# template checks `now < wake or now >= bedtime` rather than a plain range.
# Known limitation, same as ecobee-climate.nix: a restart mid-bright-window
# turns lights on bright but doesn't know how much of the window has
# elapsed, so it doesn't schedule the eventual turn-off — that only happens
# via the wake automation's own `delay` at the next scheduled wake time.
#
# "automation manual" key, not bare "automation" — see default.nix.
{lib, ...}: let
  rooms = [
    {
      room = "Abigail's Room";
      slug = "abigail";
      lights = "light.abigail_s_night_light";
    }
    {
      room = "Evelyn's Room";
      slug = "evelyn";
      lights = "light.evelyn_s_night_light";
    }
  ];

  # Dark, very dim "go to sleep" color — 1% brightness so it's a signal, not
  # reading light.
  sleepBrightnessPct = 1;
  sleepRgb = [0 0 139];

  # Bright neutral white "get up" color — 4000K is deliberately neither warm
  # (evening/relaxing) nor cool (daylight/energizing).
  wakeBrightnessPct = 100;
  wakeColorTempKelvin = 4000;
  # Kept as one number of hours (used both in the wake automations' `delay`
  # and in the startup automation's window-end template below) so the two
  # can't drift out of sync the way two independently-written "02:00:00"
  # literals could.
  wakeDurationHours = 2;
  wakeDuration = "0${toString wakeDurationHours}:00:00"; # only correct for < 10 hours

  weekdayDays = ["mon" "tue" "wed" "thu" "fri"];
  weekendDays = ["sat" "sun"];

  # Per-room helper entities, split by domain so they can be merged straight
  # into services.home-assistant.config.input_boolean/input_datetime below.
  mkBooleanHelper = {slug, ...}: {
    "${slug}_wake_lights_enabled" = {
      name = "${slug} wake lights enabled";
      icon = "mdi:weather-night";
      initial = true;
    };
  };

  mkDatetimeHelpers = {slug, ...}: {
    "${slug}_bedtime" = {
      name = "${slug} bedtime";
      has_date = false;
      has_time = true;
      initial = "18:00:00";
    };
    "${slug}_wake_weekday" = {
      name = "${slug} wake time (weekday)";
      has_date = false;
      has_time = true;
      initial = "06:00:00";
    };
    "${slug}_wake_weekend" = {
      name = "${slug} wake time (weekend)";
      has_date = false;
      has_time = true;
      initial = "07:00:00";
    };
  };

  enabledCondition = slug: {
    condition = "state";
    entity_id = "input_boolean.${slug}_wake_lights_enabled";
    state = "on";
  };

  mkSleepAutomation = {
    room,
    slug,
    lights,
    ...
  }: {
    id = "kids_wake_lights_sleep_${slug}";
    alias = "${room}: bedtime lights";
    description = "At ${room}'s bedtime (input_datetime.${slug}_bedtime), dim the lights to a very low dark blue as a go-to-sleep signal.";
    mode = "single";
    trigger = [
      {
        platform = "time";
        at = "input_datetime.${slug}_bedtime";
      }
    ];
    condition = [(enabledCondition slug)];
    action = [
      {
        service = "light.turn_on";
        target.entity_id = [lights];
        data = {
          brightness_pct = sleepBrightnessPct;
          rgb_color = sleepRgb;
        };
      }
    ];
  };

  # One per room per day-type (weekday/weekend), since the wake time and the
  # weekday-set condition both differ between the two. `dayType` is "weekday"
  # or "weekend", used for the id/alias/description and to pick the right
  # helper suffix; `days` is the matching list of HA weekday abbreviations
  # for the time condition below.
  mkWakeAutomation = {
    room,
    slug,
    lights,
    ...
  }: dayType: days: {
    id = "kids_wake_lights_wake_${slug}_${dayType}";
    alias = "${room}: ${dayType} wake lights";
    description = "At ${room}'s ${dayType} wake time (input_datetime.${slug}_wake_${dayType}), turn the lights on to bright neutral white for ${wakeDuration}, then off.";
    mode = "single";
    trigger = [
      {
        platform = "time";
        at = "input_datetime.${slug}_wake_${dayType}";
      }
    ];
    condition = [
      (enabledCondition slug)
      {
        condition = "time";
        weekday = days;
      }
    ];
    action = [
      {
        service = "light.turn_on";
        target.entity_id = [lights];
        data = {
          brightness_pct = wakeBrightnessPct;
          color_temp_kelvin = wakeColorTempKelvin;
        };
      }
      {
        delay = wakeDuration;
      }
      {
        service = "light.turn_off";
        target.entity_id = [lights];
      }
    ];
  };

  # Re-derive the desired light state on Home Assistant startup from the
  # room's own helper times, so a reboot doesn't leave lights stuck in
  # whatever state they were in before the restart. See the file header for
  # why the sleep-window comparison handles the midnight wraparound, and why
  # this doesn't replay a partially-elapsed bright window.
  mkStartupAutomation = {
    room,
    slug,
    lights,
    ...
  }: let
    bedtime = "states('input_datetime.${slug}_bedtime')";
    wakeWeekday = "states('input_datetime.${slug}_wake_weekday')";
    wakeWeekend = "states('input_datetime.${slug}_wake_weekend')";
    # Today's applicable wake time: the weekend helper on Sat/Sun, otherwise
    # the weekday helper.
    wakeToday = "(${wakeWeekend} if now().isoweekday() in [6, 7] else ${wakeWeekday})";
    nowTime = "now().strftime('%H:%M:%S')";
    # Sleep window wraps midnight (bedtime > wake), so "currently asleep"
    # means now is before today's wake time OR at/after bedtime.
    inSleepWindow = "(${nowTime} < ${wakeToday} or ${nowTime} >= ${bedtime})";
    # Bright window is [wake, wake + wakeDuration) — a fixed clock span from
    # today's applicable wake time, not tracking how much of it may have
    # already elapsed before this restart.
    inWakeWindow = "(${wakeToday} <= ${nowTime} < (today_at(${wakeToday}) + timedelta(hours=${toString wakeDurationHours})).strftime('%H:%M:%S'))";
  in {
    id = "kids_wake_lights_startup_${slug}";
    alias = "${room}: restore wake/sleep light state on startup";
    description = "On Home Assistant startup, re-derive whether ${room} should currently be in its sleep, bright-wake, or off state from the bedtime/wake helpers and set the lights accordingly. Best-effort: does not resume a partially-elapsed bright window's remaining time.";
    mode = "single";
    trigger = [
      {
        platform = "homeassistant";
        event = "start";
      }
    ];
    condition = [(enabledCondition slug)];
    action = [
      {
        choose = [
          {
            conditions = [
              {
                condition = "template";
                value_template = "{{ ${inSleepWindow} }}";
              }
            ];
            sequence = [
              {
                service = "light.turn_on";
                target.entity_id = [lights];
                data = {
                  brightness_pct = sleepBrightnessPct;
                  rgb_color = sleepRgb;
                };
              }
            ];
          }
          {
            conditions = [
              {
                condition = "template";
                value_template = "{{ ${inWakeWindow} }}";
              }
            ];
            sequence = [
              {
                service = "light.turn_on";
                target.entity_id = [lights];
                data = {
                  brightness_pct = wakeBrightnessPct;
                  color_temp_kelvin = wakeColorTempKelvin;
                };
              }
            ];
          }
        ];
        # Neither sleep nor bright-wake window -> daytime power-save off.
        default = [
          {
            service = "light.turn_off";
            target.entity_id = [lights];
          }
        ];
      }
    ];
  };
in {
  services.home-assistant.config = {
    input_boolean = lib.foldl' (acc: r: acc // mkBooleanHelper r) {} rooms;

    input_datetime = lib.foldl' (acc: r: acc // mkDatetimeHelpers r) {} rooms;

    "automation manual" =
      (map mkSleepAutomation rooms)
      ++ (map (r: mkWakeAutomation r "weekday" weekdayDays) rooms)
      ++ (map (r: mkWakeAutomation r "weekend" weekendDays) rooms)
      ++ (map mkStartupAutomation rooms);
  };
}
