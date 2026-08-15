# Home Assistant automation for reliant: ecobee thermostat schedule.
#
# The ecobees connect through the HomeKit Controller integration
# ("homekit_controller", already in extraComponents in configuration.nix for
# the outside-light switches) — local Wi-Fi control, no ecobee cloud account
# or API key. ecobee suspended new developer-key signups, so the cloud
# `ecobee` integration isn't obtainable for a new setup; local HomeKit control
# also keeps working through an internet outage.
#
# This is deliberately scoped to the hardware that actually exists today:
# two heat-only zones, main/basement and upstairs. Two more zones are
# planned but not installed — a garage thermostat (frost protection) and
# an AC for upstairs (which would turn it into a real heat/cool zone) — and
# will land as their own separate PRs once that hardware is actually in,
# rather than as feature-flagged code with nothing behind it yet. Adding a
# zone at that point means adding a new automation alongside these, not
# touching the shared helpers below.
#
# Pairing is a one-time interactive step per thermostat (mDNS discovery + the
# 8-digit HomeKit setup code shown on the thermostat's own screen) — see
# README.md § Device Pairing Notes. Each thermostat's hold action must be set
# to "Until I change it" so its own schedule never overrides the setpoint
# these automations push; otherwise a stray built-in schedule transition
# fights with HA every time they disagree. Home Assistant/HomeKit has no way
# to set this remotely — HomeKit's thermostat spec has no hold-type
# characteristic at all, confirmed against homekit_controller's own climate
# platform source — so this stays a manual one-time step regardless of how
# the automation is written.
#
# The entity IDs below are placeholders — HomeKit pairing assigns IDs from
# each thermostat's device name, which won't match this list. Rename each
# climate entity after pairing (entity cog → entity ID) to match here, or
# edit this list to match reality and rebuild. Unlike outside-lights.nix /
# door-locks.nix / presence-lighting.nix / sonos-wiim.nix, none of this has
# been run against real hardware yet — nothing here is "confirmed live".
#
# main/basement (one thermostat covering both spaces) runs 2°C warmer than
# upstairs during the day — independent absolute set points, not a delta
# computed from upstairs' value, so neither zone's schedule depends on the
# other's.
#
# Season: input_boolean.climate_summer_mode, toggled by hand (there's no
# reliable calendar or outdoor-temperature signal on this host to switch
# automatically, and Alberta's shoulder seasons don't line up with a date
# range anyway). Flipping it re-evaluates and re-applies the schedule
# immediately, same as a restart.
#
# In summer, both zones drop to a low standby heat floor (summerHeatFloor,
# 17°C) overnight and while away, instead of holding their full daytime
# comfort target — the point is to let the house cool passively overnight
# rather than have the furnace fight that by keeping it at 21-23°C. That
# requires an explicit action, not just skipping the automation: leaving the
# previous setpoint in place would still let a heat-mode thermostat heat
# back up to its last (comfort) target overnight. hvac_mode "off" was
# considered instead of a low floor, but this house does get occasional
# summer cold spells — an active low floor still protects against those,
# where "off" wouldn't.
#
# Restart-resilient in the same spirit as presence-lighting.nix: each zone
# is one automation re-evaluating a single `choose` block of "what should
# this zone be doing right now" against several triggers (schedule times,
# presence edges, the season toggle flipping, that zone's manual-override
# timer elapsing, and Home Assistant startup) rather than one automation per
# transition. `choose` evaluates branches in order and stops at the first
# match, so branch order encodes priority — see mkHeatOnlyZone below.
#
# Manual override: a human changing a thermostat's target temperature or
# mode — at the unit, in the ecobee app, or via HomeKit/Home Assistant
# itself — starts a 2-hour per-zone timer
# (timer.climate_override_main_and_basement / _upstairs) and suppresses
# that zone's comfort/setback branches until it elapses, so the schedule
# doesn't fight a deliberate change a few minutes after it's made. The away
# branches are deliberately NOT gated by it — an empty house should still
# save energy even if a hold was left active.
#
# Detection relies on trigger.to_state.context.parent_id, not user_id.
# user_id is only set for a service call issued directly by a logged-in HA
# user through the frontend/API — confirmed against HA's own core.py and
# automation/__init__.py, it's null both for this file's own automation
# calls AND for a state pushed in externally (the ecobee reporting a change
# made at the unit, in its app, or via HomeKit), so it never actually
# distinguished the two. parent_id does: HA's automation engine sets it to
# the triggering run's context ID for every service call an automation
# makes, while an externally-pushed state update gets a fresh context with
# no parent at all. So parent_id present means "this file's own automation
# caused it"; parent_id absent means anything else did — a person at the
# thermostat, in its app, via HomeKit, or even via the HA frontend.
{
  services.home-assistant.config = {
    timer = {
      climate_override_main_and_basement = {
        name = "Climate override — main/basement";
        icon = "mdi:thermostat";
        duration = "02:00:00";
      };
      climate_override_upstairs = {
        name = "Climate override — upstairs";
        icon = "mdi:thermostat";
        duration = "02:00:00";
      };
    };

    input_boolean.climate_summer_mode = {
      name = "Climate — summer mode";
      icon = "mdi:sun-thermometer";
      initial = false;
    };

    "automation manual" = let
      mainAndBasement = "climate.main_and_basement";
      upstairs = "climate.upstairs";

      wakeTime = "05:30:00";
      sleepTime = "22:00:00";

      mainAndBasementComfort = 23; # 2°C above upstairs' comfort — independent constant, not a formula.
      mainAndBasementSetback = 18; # winter night only.
      mainAndBasementAway = 16; # winter only.

      upstairsComfort = 21;
      upstairsSetback = 18; # winter night only.
      upstairsAway = 16; # winter only.

      # Summer standby: an active low heat floor, not "off" — this house
      # gets occasional summer cold spells, and a floor still protects
      # against those where turning heat off entirely wouldn't.
      summerHeatFloor = 17;

      setTemp = entityId: temperature: {
        service = "climate.set_temperature";
        target.entity_id = entityId;
        data.temperature = temperature;
      };

      presentCondition = {
        condition = "numeric_state";
        entity_id = "zone.home";
        above = 0;
      };

      notPresentCondition = {
        condition = "numeric_state";
        entity_id = "zone.home";
        below = 1;
      };

      dayCondition = {
        condition = "time";
        after = wakeTime;
        before = sleepTime;
      };

      summerCondition = {
        condition = "state";
        entity_id = "input_boolean.climate_summer_mode";
        state = "on";
      };

      winterCondition = {
        condition = "state";
        entity_id = "input_boolean.climate_summer_mode";
        state = "off";
      };

      notOverridden = timerEntityId: {
        condition = "state";
        entity_id = timerEntityId;
        state = "idle";
      };

      # Shared trigger set: the daily schedule times, both presence edges
      # (arrival immediate, departure after a 15 minute grace so a quick
      # errand doesn't cycle the setpoint), the season toggle changing,
      # this zone's override timer elapsing, and Home Assistant startup.
      zoneTriggers = overrideTimerEntityId: [
        {
          platform = "time";
          at = wakeTime;
        }
        {
          platform = "time";
          at = sleepTime;
        }
        {
          platform = "numeric_state";
          entity_id = "zone.home";
          above = 0;
        }
        {
          platform = "numeric_state";
          entity_id = "zone.home";
          below = 1;
          for = "00:15:00";
        }
        {
          platform = "state";
          entity_id = "input_boolean.climate_summer_mode";
        }
        {
          platform = "event";
          event_type = "timer.finished";
          event_data.entity_id = overrideTimerEntityId;
        }
        {
          platform = "homeassistant";
          event = "start";
        }
      ];

      # A complete heat-only zone: comfort during the day, setback at night
      # in winter, the standby floor at night/away in summer, away setback
      # in winter — all re-evaluated on every trigger in zoneTriggers.
      # Both main/basement and upstairs are this shape today; a zone that
      # gains real cooling (or a new zone like the garage) needs its own
      # automation, not a change here.
      mkHeatOnlyZone = {
        id,
        alias,
        entityId,
        timerEntityId,
        comfortTemp,
        setbackTemp,
        awayTemp,
      }: {
        inherit id alias;
        description = "Re-evaluate ${entityId}'s desired temperature on every schedule time, presence edge, season change, override expiry, and restart.";
        mode = "single";
        trigger = zoneTriggers timerEntityId;
        action = [
          {
            choose = [
              # Comfort: home, daytime, not currently overridden. Season
              # doesn't change the daytime target for a heat-only zone.
              {
                conditions = [presentCondition dayCondition (notOverridden timerEntityId)];
                sequence = [(setTemp entityId comfortTemp)];
              }
              # Setback: home, night, winter, not overridden.
              {
                conditions = [presentCondition winterCondition (notOverridden timerEntityId)];
                sequence = [(setTemp entityId setbackTemp)];
              }
              # Setback, summer: the standby floor, not just "no action" —
              # see the file header for why leaving the prior (comfort)
              # setpoint in place wouldn't actually reduce overnight heating.
              {
                conditions = [presentCondition summerCondition (notOverridden timerEntityId)];
                sequence = [(setTemp entityId summerHeatFloor)];
              }
              # Away, winter: heat to the away setback regardless of any
              # active override — leaving the house should always save
              # energy.
              {
                conditions = [notPresentCondition winterCondition];
                sequence = [(setTemp entityId awayTemp)];
              }
              # Away, summer: the standby floor, same reasoning as the
              # summer setback branch, also regardless of override.
              {
                conditions = [notPresentCondition summerCondition];
                sequence = [(setTemp entityId summerHeatFloor)];
              }
            ];
            # Only reached if every present-and-home branch above was
            # suppressed by an active override — both away branches (winter
            # and summer) are unconditional, so one of them always matches
            # when nobody's home.
            default = [];
          }
        ];
      };

      overrideStartAutomation = {
        id,
        alias,
        entityId,
        timerEntityId,
      }: {
        inherit id alias;
        description = "A person (not this file's own automations) changed ${entityId}'s target temperature or mode — start/restart its override timer so the schedule leaves it alone for a while.";
        mode = "queued";
        trigger = [
          {
            platform = "state";
            entity_id = entityId;
            attribute = "temperature";
          }
          # No `attribute:` here — a plain state trigger fires on the
          # entity's own state, which for a climate entity *is* hvac_mode.
          # Without this, manually switching a thermostat's mode (e.g. to
          # off) goes completely undetected: nothing starts the override
          # timer, so the schedule silently overwrites it at the next
          # trigger instead of leaving it alone for a while.
          {
            platform = "state";
            entity_id = entityId;
          }
        ];
        condition = [
          {
            condition = "template";
            # parent_id, not user_id — see the file header for why. This is
            # the check that actually distinguishes this file's own
            # climate.set_temperature/set_hvac_mode calls from anything
            # external (thermostat, ecobee app, HomeKit, or the HA
            # frontend) pushing a state change in.
            #
            # trigger.attribute is none only for the plain (no `attribute:`)
            # trigger above — confirmed against HA's state trigger source,
            # a bare state trigger's match_all fires on ANY attribute
            # changing, not just hvac_mode (the entity's actual .state).
            # Without the from/to .state comparison here, every routine
            # telemetry push from the ecobee (current_temperature drifting,
            # humidity, etc. — frequent, and external, so parent_id is none
            # for those too) passed this condition and restarted the
            # override timer, so it never went idle. The attribute-scoped
            # trigger above doesn't need this: HA's own attribute filtering
            # already only fires it on a real change to "temperature".
            value_template = "{{ trigger.to_state.context.parent_id is none and (trigger.attribute is not none or trigger.from_state.state != trigger.to_state.state) }}";
          }
        ];
        # timer.start on an already-running timer restarts it from the full
        # configured duration, so repeated manual nudges keep extending the
        # override rather than letting an earlier one expire mid-adjustment.
        action = [
          {
            service = "timer.start";
            target.entity_id = timerEntityId;
          }
        ];
      };
    in [
      (mkHeatOnlyZone {
        id = "climate_main_and_basement";
        alias = "Climate — main/basement schedule";
        entityId = mainAndBasement;
        timerEntityId = "timer.climate_override_main_and_basement";
        comfortTemp = mainAndBasementComfort;
        setbackTemp = mainAndBasementSetback;
        awayTemp = mainAndBasementAway;
      })
      (mkHeatOnlyZone {
        id = "climate_upstairs";
        alias = "Climate — upstairs schedule";
        entityId = upstairs;
        timerEntityId = "timer.climate_override_upstairs";
        comfortTemp = upstairsComfort;
        setbackTemp = upstairsSetback;
        awayTemp = upstairsAway;
      })
      (overrideStartAutomation {
        id = "climate_override_start_main_and_basement";
        alias = "Climate — start manual override (main/basement)";
        entityId = mainAndBasement;
        timerEntityId = "timer.climate_override_main_and_basement";
      })
      (overrideStartAutomation {
        id = "climate_override_start_upstairs";
        alias = "Climate — start manual override (upstairs)";
        entityId = upstairs;
        timerEntityId = "timer.climate_override_upstairs";
      })
    ];
  };
}
