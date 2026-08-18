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
# Season: input_boolean.climate_summer_mode. climate_summer_mode_season_default
# (below) sets it once at each boundary — on May 1, off October 1 — since
# Alberta's shoulder seasons don't line up with a fixed date range closely
# enough to enforce it continuously, and a hand-flip in between (an early
# heat wave, a late cold snap) should stick rather than get fought back to
# the calendar's opinion at the next check. Flipping it, by hand or by that
# automation, re-evaluates and re-applies the schedule immediately, same as
# a restart.
#
# In summer, both zones drop to a low standby heat floor at all times, not
# just overnight/away — real-world testing found the original version (full
# daytime comfort target even in summer, on the reasoning that a heat-only
# zone with no AC doesn't need a different daytime target) just heats the
# house to 21-23°C on a summer day for no reason. Each zone has its own
# floor (input_number.climate_main_and_basement_summer_floor, initially
# 20°C; input_number.climate_upstairs_summer_floor, initially 19°C), not a
# shared value — the first shared value (17°C) also turned out too cold for
# main/basement once tested live; independent per-zone numbers, not a delta
# between them. All the set points below (comfort/setback/away/summer
# floor, per zone) are input_number helpers rather than fixed constants —
# see liveTemp — so they're adjustable from the dashboard without a
# redeploy. hvac_mode "off" was considered instead of a low floor, but this
# house does get occasional summer cold spells — an active low floor still
# protects against those, where "off" wouldn't. That's also why this is an
# explicit action, not just skipping the automation: leaving the previous
# setpoint in place would still let a heat-mode thermostat heat back up to
# whatever it was holding before.
#
# Each zone also reasserts hvac_mode "heat" alongside every setpoint, not
# just temperature — confirmed live that this file never called
# set_hvac_mode at all originally, so an external mode change (upstairs was
# found switched to "off" with no override active and no explanation)
# could never self-correct. Composes with the override timer below: a
# manual mode change still starts that zone's 2-hour override, so this only
# reasserts once it elapses.
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
# Detection compares the incoming state against a per-zone "last commanded"
# snapshot (input_text.climate_last_commanded_*, "<hvac_mode>|<temperature>"),
# not context — two things this file already tried and both failed for the
# same underlying reason. context.user_id is only set for a service call
# issued directly by a logged-in HA user through the frontend/API, so it was
# null both for this file's own calls and for an externally-pushed state.
# context.parent_id looked right (HA's automation engine does set it to the
# triggering run's context ID for every service call an automation makes)
# and tested fine against a real external change — but confirmed against
# homekit_controller's own climate platform source: its
# async_set_temperature/async_set_hvac_mode only send the HomeKit command
# and return; the entity's actual state write happens later, from a
# separate callback triggered by the thermostat pushing a
# characteristic-changed notification back, running outside the original
# service call entirely. That callback's state write gets a fresh context
# with no parent regardless of who caused the underlying change — so
# parent_id was none both for a person's change AND for this file's own
# setTemp calls, once the resulting push-back actually arrived. Confirmed
# live: right after a deploy that changed the standby floor, both zones'
# override timers started simultaneously, from mkHeatOnlyZone's own startup
# trigger re-asserting the new setpoint. Comparing by value instead of
# context sidesteps the problem entirely: setTemp records what it just
# commanded before the HomeKit round-trip even starts, so by the time the
# real state change arrives — from this file or from anywhere else — it's
# either an exact match (ours) or it isn't (someone else's).
#
# notLastCommanded also requires a real prior state (not none/unavailable/
# unknown) before treating a mismatch as external. Confirmed live: without
# that guard, restarting HA still started the override immediately and
# incorrectly — the climate entity's transition from unavailable to its
# last real state, as homekit_controller reconnects, looks exactly like an
# unexplained external change (nothing's in last-commanded yet on a fresh
# boot), and since it isn't guaranteed to lose the race against the
# schedule's own startup-triggered correction, it could win and lock the
# schedule out of applying anything correct for the full 2 hours. A restart
# is the entity coming back online, not a person acting on it.
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

    # No `initial:` here — deliberately. Confirmed against input_boolean's
    # own source (async_added_to_hass): specifying `initial` bypasses
    # RestoreEntity entirely, so the value resets to that initial constant
    # on every single restart, not just first-ever creation. Confirmed
    # live: this reset climate_summer_mode to "off" on every
    # nixos-rebuild switch, silently discarding a hand-flip minutes
    # earlier and undoing exactly the "respected on reload until a season
    # boundary" behavior this file is supposed to have. Without `initial`,
    # it restores its last real state on restart and only falls back to
    # its constructor default (off) the first time this entity ever
    # exists with no history at all.
    input_boolean.climate_summer_mode = {
      name = "Climate — summer mode";
      icon = "mdi:sun-thermometer";
    };

    # "<hvac_mode>|<temperature>" snapshot of the last setpoint this file
    # itself commanded for each zone — see the file header for why this
    # replaced context.parent_id as the override-detection mechanism.
    #
    # Deliberately no `initial:` here either — same input_boolean/
    # input_number bug (see above), confirmed against input_text's own
    # source too: `initial` sets self._attr_native_value in __init__,
    # which makes async_added_to_hass's restore attempt a no-op. Confirmed
    # live: the fromKnown guard on notLastCommanded alone wasn't enough to
    # stop the override starting on a restart, because even once
    # notLastCommanded correctly recognized the climate entity's own
    # from_state as real (not a coming-online transition), the comparison
    # itself was checking against a snapshot that had just been wiped
    # back to "" by this same restart — so any real setTemp call the
    # schedule made right after boot (e.g. because time had crossed a
    # wake/sleep boundary during downtime) couldn't match anything and
    # was flagged as external every time. Without `initial`, this
    # restores its last real value across restarts, same as the actual
    # thermostat state does.
    input_text = {
      climate_last_commanded_main_and_basement = {
        name = "Climate — last commanded (main/basement)";
      };
      climate_last_commanded_upstairs = {
        name = "Climate — last commanded (upstairs)";
      };
    };

    # Live-adjustable set points — the automation below reads these at
    # evaluation time instead of closing over fixed Nix constants, so a
    # target can be tuned from the dashboard without a redeploy.
    #
    # Deliberately no `initial:` here — confirmed against input_number's
    # own source (async_added_to_hass): `self._attr_native_value` is set
    # from `initial` inside `__init__`, before async_added_to_hass ever
    # runs, and that method's very first check is `if
    # self._attr_native_value is not None: return` — so specifying
    # `initial` skips RestoreEntity entirely, identical to
    # input_boolean's version of this bug (see climate_summer_mode
    # above), and would reset every slider to these numbers on every
    # single restart, defeating the entire point of making them
    # dashboard-adjustable.
    #
    # But unlike a boolean, input_number's OWN fallback when there's
    # nothing to restore is native_min_value (10°C here) — not a sensible
    # default, and unsafe to even briefly command as a real target. So
    # first-boot seeding is handled explicitly below (climate_set_points_seeded
    # + "Climate — seed set points") instead of via `initial`.
    input_number = {
      climate_main_and_basement_comfort = {
        name = "Main/basement — comfort";
        icon = "mdi:thermometer";
        unit_of_measurement = "°C";
        min = 10;
        max = 28;
        step = 0.5;
      };
      climate_main_and_basement_setback = {
        name = "Main/basement — setback (winter night)";
        icon = "mdi:thermometer-low";
        unit_of_measurement = "°C";
        min = 10;
        max = 28;
        step = 0.5;
      };
      climate_main_and_basement_away = {
        name = "Main/basement — away (winter)";
        icon = "mdi:thermometer-low";
        unit_of_measurement = "°C";
        min = 10;
        max = 28;
        step = 0.5;
      };
      climate_main_and_basement_summer_floor = {
        name = "Main/basement — summer floor";
        icon = "mdi:thermometer-low";
        unit_of_measurement = "°C";
        min = 10;
        max = 28;
        step = 0.5;
      };
      climate_upstairs_comfort = {
        name = "Upstairs — comfort";
        icon = "mdi:thermometer";
        unit_of_measurement = "°C";
        min = 10;
        max = 28;
        step = 0.5;
      };
      climate_upstairs_setback = {
        name = "Upstairs — setback (winter night)";
        icon = "mdi:thermometer-low";
        unit_of_measurement = "°C";
        min = 10;
        max = 28;
        step = 0.5;
      };
      climate_upstairs_away = {
        name = "Upstairs — away (winter)";
        icon = "mdi:thermometer-low";
        unit_of_measurement = "°C";
        min = 10;
        max = 28;
        step = 0.5;
      };
      climate_upstairs_summer_floor = {
        name = "Upstairs — summer floor";
        icon = "mdi:thermometer-low";
        unit_of_measurement = "°C";
        min = 10;
        max = 28;
        step = 0.5;
      };
    };

    # Internal marker, not shown on the dashboard: flips on the first time
    # "Climate — seed set points" (below) has ever run, so that seeding
    # happens exactly once, ever — not on every restart, which would
    # reintroduce the same reset-on-reload problem this file just moved
    # away from for the set points themselves. No `initial:` here either,
    # for the same reason: this needs to actually persist as "already
    # seeded" across restarts, not reset to "not seeded" on every one.
    input_boolean.climate_set_points_seeded = {
      name = "Climate — set points seeded";
      icon = "mdi:cog";
    };

    "automation manual" = let
      mainAndBasement = "climate.main_and_basement";
      upstairs = "climate.upstairs";

      wakeTime = "05:30:00";
      sleepTime = "22:00:00";

      # Reads a set point from its input_number at evaluation time, as a
      # Jinja template string rather than a Nix number — every consumer
      # downstream (climate.set_temperature's data.temperature, and the
      # last-commanded snapshot written alongside it) is itself a plain
      # string-valued service-call field, which Home Assistant renders as a
      # template automatically. Both calls render the same input_number at
      # nearly the same instant, so they agree even though the actual
      # number now lives in HA state rather than being baked in at build
      # time.
      liveTemp = entityId: "{{ states('${entityId}') | float }}";

      # Records what this file itself just commanded, so overrideStartAutomation
      # can recognize its own handiwork arriving back as a state change — see
      # the file header for why context.parent_id can't do this job.
      setLastCommanded = lastCommandedEntityId: mode: temperature: {
        service = "input_text.set_value";
        target.entity_id = lastCommandedEntityId;
        data.value = "${mode}|${toString temperature}";
      };

      # lastCommandedEntityId is null for a zone with no override automation
      # to feed (garage: a frost-protection floor, not a schedule a person
      # would want to temporarily suspend) — skips the tracking write
      # entirely rather than creating an input_text nothing ever reads.
      setTemp = entityId: temperature: lastCommandedEntityId:
        [
          {
            service = "climate.set_temperature";
            target.entity_id = entityId;
            # hvac_mode alongside temperature in the same call (climate.
            # set_temperature accepts both) — these are heat-only zones, so
            # every re-evaluation reasserts "heat" too, not just the setpoint.
            # Confirmed live: upstairs was found in hvac_mode "off" with no
            # override active and no explanation — this file never called
            # set_hvac_mode at all before, so nothing here could have caused
            # it, but nothing here could correct it either. Composes with the
            # existing override detection below: a person switching a
            # thermostat off is still a mode change, still starts that zone's
            # 2-hour override timer, so this only reasserts once that elapses.
            data = {
              inherit temperature;
              hvac_mode = "heat";
            };
          }
        ]
        ++ (
          if lastCommandedEntityId == null
          then []
          else [(setLastCommanded lastCommandedEntityId "heat" temperature)]
        );

      # True when the incoming state doesn't match what this file itself
      # last commanded for this zone — i.e. genuinely came from outside.
      # Compares by value (mode + temperature), not by context, since
      # homekit_controller's state updates never carry a usable context at
      # all — see the file header.
      #
      # Also requires a real prior state, not unavailable/unknown/none:
      # confirmed live that without this, the override started immediately
      # on every restart and won the race against the schedule's own
      # startup trigger — the climate entity's transition from unavailable
      # to its last real state, as homekit_controller reconnects, looks
      # exactly like an unexplained external change (nothing's been
      # recorded in last-commanded yet), and if that fires first, the
      # override locks the schedule out of ever applying the correct value
      # for the full 2 hours. A restart is the entity coming back online,
      # not a person acting.
      notLastCommanded = lastCommandedEntityId: {
        condition = "template";
        value_template = ''
          {% set parts = states('${lastCommandedEntityId}').split('|') %}
          {% set expectedMode = parts[0] if parts | length > 0 else ''' %}
          {% set expectedTemp = parts[1] | float(-999) if parts | length > 1 else -999 %}
          {% set fromKnown = trigger.from_state is not none and trigger.from_state.state not in ['unavailable', 'unknown'] %}
          {{ fromKnown and not (trigger.to_state.state == expectedMode and (trigger.to_state.attributes.temperature | float(-998)) == expectedTemp) }}
        '';
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
      # this zone's set points changing (so a dashboard slider tweak
      # applies immediately, the same as the season toggle already does —
      # otherwise it would silently wait for the next schedule trigger),
      # this zone's override timer elapsing, and Home Assistant startup.
      zoneTriggers = overrideTimerEntityId: setPointEntityIds:
        [
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
        ]
        ++ map (entityId: {
          platform = "state";
          entity_id = entityId;
        })
        setPointEntityIds
        ++ [
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
        lastCommandedEntityId,
        setPointEntityIds,
        comfortTemp,
        setbackTemp,
        awayTemp,
        summerFloorTemp,
      }: {
        inherit id alias;
        description = "Re-evaluate ${entityId}'s desired temperature on every schedule time, presence edge, season change, set point change, override expiry, and restart.";
        mode = "single";
        trigger = zoneTriggers timerEntityId setPointEntityIds;
        action = [
          {
            choose = [
              # Comfort: home, daytime, winter, not currently overridden.
              {
                conditions = [presentCondition dayCondition winterCondition (notOverridden timerEntityId)];
                sequence = setTemp entityId comfortTemp lastCommandedEntityId;
              }
              # Setback: home, night, winter, not overridden.
              {
                conditions = [presentCondition winterCondition (notOverridden timerEntityId)];
                sequence = setTemp entityId setbackTemp lastCommandedEntityId;
              }
              # Summer, home, not overridden: the standby floor regardless
              # of day/night. Confirmed live: the original version of this
              # zone kept the day-comfort branch season-blind (day always
              # meant comfortTemp, even in summer), on the reasoning that a
              # heat-only zone with no AC doesn't need a different daytime
              # target in summer — real-world testing in August showed
              # that's wrong: nobody wants full comfort-temp heating on a
              # summer day just because they're home. Summer now collapses
              # to one target (the floor) at all times while present, same
              # as it already did while away — not just "no action", since
              # leaving the prior setpoint in place would still let a
              # heat-mode thermostat heat back up to whatever it was
              # holding before.
              {
                conditions = [presentCondition summerCondition (notOverridden timerEntityId)];
                sequence = setTemp entityId summerFloorTemp lastCommandedEntityId;
              }
              # Away, winter: heat to the away setback regardless of any
              # active override — leaving the house should always save
              # energy.
              {
                conditions = [notPresentCondition winterCondition];
                sequence = setTemp entityId awayTemp lastCommandedEntityId;
              }
              # Away, summer: the standby floor, same reasoning as the
              # summer setback branch, also regardless of override.
              {
                conditions = [notPresentCondition summerCondition];
                sequence = setTemp entityId summerFloorTemp lastCommandedEntityId;
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
        lastCommandedEntityId,
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
        # notLastCommanded, not context.parent_id — see the file header for
        # why. This is the check that distinguishes this file's own
        # climate.set_temperature calls from anything external (thermostat,
        # ecobee app, HomeKit, or the HA frontend) pushing a state change
        # in, by comparing the resulting state against what setTemp last
        # recorded for this zone rather than by context.
        condition = [(notLastCommanded lastCommandedEntityId)];
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
        lastCommandedEntityId = "input_text.climate_last_commanded_main_and_basement";
        setPointEntityIds = [
          "input_number.climate_main_and_basement_comfort"
          "input_number.climate_main_and_basement_setback"
          "input_number.climate_main_and_basement_away"
          "input_number.climate_main_and_basement_summer_floor"
        ];
        comfortTemp = liveTemp "input_number.climate_main_and_basement_comfort";
        setbackTemp = liveTemp "input_number.climate_main_and_basement_setback";
        awayTemp = liveTemp "input_number.climate_main_and_basement_away";
        summerFloorTemp = liveTemp "input_number.climate_main_and_basement_summer_floor";
      })
      (mkHeatOnlyZone {
        id = "climate_upstairs";
        alias = "Climate — upstairs schedule";
        entityId = upstairs;
        timerEntityId = "timer.climate_override_upstairs";
        lastCommandedEntityId = "input_text.climate_last_commanded_upstairs";
        setPointEntityIds = [
          "input_number.climate_upstairs_comfort"
          "input_number.climate_upstairs_setback"
          "input_number.climate_upstairs_away"
          "input_number.climate_upstairs_summer_floor"
        ];
        comfortTemp = liveTemp "input_number.climate_upstairs_comfort";
        setbackTemp = liveTemp "input_number.climate_upstairs_setback";
        awayTemp = liveTemp "input_number.climate_upstairs_away";
        summerFloorTemp = liveTemp "input_number.climate_upstairs_summer_floor";
      })
      (overrideStartAutomation {
        id = "climate_override_start_main_and_basement";
        alias = "Climate — start manual override (main/basement)";
        entityId = mainAndBasement;
        timerEntityId = "timer.climate_override_main_and_basement";
        lastCommandedEntityId = "input_text.climate_last_commanded_main_and_basement";
      })
      (overrideStartAutomation {
        id = "climate_override_start_upstairs";
        alias = "Climate — start manual override (upstairs)";
        entityId = upstairs;
        timerEntityId = "timer.climate_override_upstairs";
        lastCommandedEntityId = "input_text.climate_last_commanded_upstairs";
      })
      {
        id = "climate_summer_mode_season_default";
        alias = "Climate — summer mode seasonal default";
        description = "Sets input_boolean.climate_summer_mode at each seasonal boundary (on May 1, off October 1) and leaves it alone the rest of the year — a hand-flip in between (e.g. an early heat wave) sticks until the next boundary, same as flipping it any other day.";
        mode = "single";
        trigger = [
          {
            platform = "time";
            at = "00:05:00";
          }
        ];
        action = [
          {
            choose = [
              {
                conditions = [
                  {
                    condition = "template";
                    value_template = "{{ now().month == 5 and now().day == 1 }}";
                  }
                ];
                sequence = [
                  {
                    service = "input_boolean.turn_on";
                    target.entity_id = "input_boolean.climate_summer_mode";
                  }
                ];
              }
              {
                conditions = [
                  {
                    condition = "template";
                    value_template = "{{ now().month == 10 and now().day == 1 }}";
                  }
                ];
                sequence = [
                  {
                    service = "input_boolean.turn_off";
                    target.entity_id = "input_boolean.climate_summer_mode";
                  }
                ];
              }
            ];
            # Every other day: no action, deliberately — not a bug to
            # guard against, just the 363 days a year this doesn't apply.
            default = [];
          }
        ];
      }
      {
        id = "climate_seed_set_points";
        alias = "Climate — seed set points";
        description = "Runs exactly once, ever: sets the eight set-point input_numbers to their original sensible defaults, then flips climate_set_points_seeded on so this never runs again. Only exists because input_number's own restore-on-restart is incompatible with also specifying an `initial:` (see the input_number block above) — without this, a fresh deployment would start every set point at its unsafe 10°C floor until someone visits the dashboard.";
        mode = "single";
        trigger = [
          {
            platform = "homeassistant";
            event = "start";
          }
        ];
        condition = [
          {
            condition = "state";
            entity_id = "input_boolean.climate_set_points_seeded";
            state = "off";
          }
        ];
        action = [
          {
            service = "input_number.set_value";
            target.entity_id = "input_number.climate_main_and_basement_comfort";
            data.value = 23;
          }
          {
            service = "input_number.set_value";
            target.entity_id = "input_number.climate_main_and_basement_setback";
            data.value = 18;
          }
          {
            service = "input_number.set_value";
            target.entity_id = "input_number.climate_main_and_basement_away";
            data.value = 16;
          }
          {
            service = "input_number.set_value";
            target.entity_id = "input_number.climate_main_and_basement_summer_floor";
            data.value = 20;
          }
          {
            service = "input_number.set_value";
            target.entity_id = "input_number.climate_upstairs_comfort";
            data.value = 21;
          }
          {
            service = "input_number.set_value";
            target.entity_id = "input_number.climate_upstairs_setback";
            data.value = 18;
          }
          {
            service = "input_number.set_value";
            target.entity_id = "input_number.climate_upstairs_away";
            data.value = 16;
          }
          {
            service = "input_number.set_value";
            target.entity_id = "input_number.climate_upstairs_summer_floor";
            data.value = 19;
          }
          {
            service = "input_boolean.turn_on";
            target.entity_id = "input_boolean.climate_set_points_seeded";
          }
        ];
      }
    ];
  };
}
