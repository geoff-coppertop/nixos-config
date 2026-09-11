# Home Assistant automation for reliant: WiZ outdoor lights — seasonal color
# and power-loss recovery.
#
# PLACEHOLDER ENTITY IDS — the 5 WiZ bulbs below are not paired yet (this
# file has a hard runtime dependency on the "wiz" extraComponents entry,
# added by a separate PR, being merged and deployed first). Every
# light.front_wiz_*/light.rear_wiz literal here must be replaced with the
# real entity ID HA assigns at pairing time, then verified with
# `nix run .#check-ha-entities -- reliant` (see docs/operations.md) before
# this ships. The switch.front_entry_lights -> front group / switch.
# patio_lights -> rear group mapping below is confirmed with the user, not
# a guess.
#
# ## Why this exists
#
# The WiZ bulbs sit behind the same two AC circuits
# hosts/reliant/home-assistant/outside-lights.nix already schedules on/off
# (switch.front_entry_lights, switch.patio_lights — see that file for the
# dark/window scheduling logic, which this file does not duplicate). Cutting
# power resets a WiZ bulb's brightness/color-temp/color to its own factory
# default; there is no way to make it remember its own state across a power
# cycle. This file makes Home Assistant do that remembering instead:
# whatever a bulb was last commanded to (by the seasonal automation below or
# by hand, e.g. the WiZ app) is continuously snapshotted into a scene, and
# restored whenever a bulb comes back from `unavailable` outside of a normal
# scheduled switch-on.
#
# ## Fixture model (5 bulbs)
#
# Front (4): one light always stays plain warm white, never seasonal. The
# other three show the season's colors simultaneously, split 2/1 (two show
# color A, one shows color B) — there are enough of them to not need to
# alternate over time.
# Rear (1): alone, so for a two-color season it alternates between color A
# and color B by day (even/odd day-of-month) instead of splitting.
#
# ## Seasonal palette (evening-only, i.e. gated the same "dark AND inside a
# scheduled window" way outside-lights.nix already gates switch-on — this
# only ever runs as a reaction to that switch turning on, so it's implicitly
# already inside that gate)
#
#   October            orange, single color, every seasonal light the same
#   December            red (A) / green (B)
#   Feb 1st-14th        red (A) / pink (B)
#   any other time      warm white (~2700K), same as the always-white light
#
# `color_temp_kelvin` (not the legacy `color_temp` mireds field) is used for
# warm white: checked directly against this flake's pinned nixpkgs revision
# (NixOS/nixpkgs ffb3c9b7, ~2026-08-19) — `light.turn_on`'s voluptuous schema
# at that Home Assistant version only accepts `color_temp_kelvin`; `color_temp`
# is not in the schema at all any more, so the legacy field would be rejected
# outright rather than merely deprecated. `color_name` (e.g. "orange", "red")
# is used for the seasonal colors — simpler and more readable here than raw
# RGB, and present in the same schema.
#
# ## The three automations
#
# A (x2, front/rear): the backing switch turning on -> after a short delay
#    for the bulb to power up and rejoin Wi-Fi, apply the season's colors
#    (or warm white, off-season). This is the normal scheduled path.
# B: any WiZ light settling into "on" (whether from A above or a manual
#    change via the app) -> snapshot all 5 into one shared scene. This is
#    what "last commanded state" means below — always the most recent
#    explicit command, automation or manual.
# C: a WiZ light going from "unavailable" to anything, but ONLY once its
#    backing switch has already been "on" for a while (not just turned on
#    as part of A's own schedule this instant) -> restore the snapshot
#    instead of recomputing the season fresh. This is what makes a manual
#    tweak (dimmed via the app, say) survive a brief mid-evening Wi-Fi drop
#    without A's next scheduled edge silently reverting it.
#
# B deliberately excludes the exact `unavailable -> on` transition C acts
# on, so the two never race over the same event — B re-snapshotting a
# bulb's just-reset factory-default state at the same instant C is trying
# to restore from it would be exactly backwards.
#
# ## Known gap
#
# If a bulb takes longer than the post-power-on delay below to rejoin
# Wi-Fi after a *scheduled* switch-on, automation A's light.turn_on call
# can land on a still-unavailable entity and no-op for that bulb — and C
# deliberately does not step in during that same window (the switch looks
# like it just turned on as scheduled, which is the normal case C must
# leave alone). That bulb is left at its own factory default until the
# next scheduled edge. Documented as a real trade-off of "one delayed
# shot" rather than a retry loop, not silently accepted.
#
# Declared under the "automation manual" key (not bare "automation"), same
# as every other file in this directory — see default.nix.
let
  frontSwitch = "switch.front_entry_lights";
  rearSwitch = "switch.patio_lights";

  frontWizWhite = "light.front_wiz_white";
  frontWizA1 = "light.front_wiz_a1";
  frontWizA2 = "light.front_wiz_a2";
  frontWizB1 = "light.front_wiz_b1";
  rearWiz = "light.rear_wiz";

  frontWizA = [frontWizA1 frontWizA2];
  frontWizB = [frontWizB1];
  allWizLights = [frontWizWhite frontWizA1 frontWizA2 frontWizB1 rearWiz];

  brightnessPct = 100; # default; tune to taste, nothing in the request pins this
  warmWhiteKelvin = 2700;
  postPowerOnDelay = "00:00:08"; # bulb boot/Wi-Fi rejoin grace after the switch turns on
  reconnectGraceSeconds = 600; # must exceed postPowerOnDelay by a wide margin — see automation C

  sceneId = "wiz_last_known_state";
  sceneEntity = "scene.${sceneId}";

  # A choose-block generator: three seasonal windows plus a default,
  # parameterized by how each group actually applies a color pair
  # (front's simultaneous split vs. rear's day-parity alternation are
  # different action shapes, so only the month/day branching is shared).
  mkSeasonalChoose = actionsFn: defaultEntities: {
    choose = [
      {
        conditions = [{condition = "template"; value_template = "{{ now().month == 10 }}";}];
        # October is single-color: passing the same color as both A and B
        # collapses cleanly into the two-color machinery below (rear's
        # alternating template evaluates to "orange" either way) — a
        # deliberate simplification, not a missing case.
        sequence = actionsFn "orange" "orange";
      }
      {
        conditions = [{condition = "template"; value_template = "{{ now().month == 12 }}";}];
        sequence = actionsFn "red" "green";
      }
      {
        conditions = [{condition = "template"; value_template = "{{ now().month == 2 and now().day <= 14 }}";}];
        sequence = actionsFn "red" "pink";
      }
    ];
    default = [
      {
        service = "light.turn_on";
        target.entity_id = defaultEntities;
        data = {
          color_temp_kelvin = warmWhiteKelvin;
          brightness_pct = brightnessPct;
        };
      }
    ];
  };

  # Front's 3 seasonal lights split 2/1 across the pair, simultaneously.
  mkFrontSeasonalActions = colorA: colorB: [
    {
      service = "light.turn_on";
      target.entity_id = frontWizA;
      data = {
        color_name = colorA;
        brightness_pct = brightnessPct;
      };
    }
    {
      service = "light.turn_on";
      target.entity_id = frontWizB;
      data = {
        color_name = colorB;
        brightness_pct = brightnessPct;
      };
    }
  ];

  # Rear's single light alternates between the pair by day, since it has no
  # sibling to split with.
  mkRearSeasonalActions = colorA: colorB: [
    {
      service = "light.turn_on";
      target.entity_id = [rearWiz];
      data = {
        color_name = "{{ '${colorA}' if now().day % 2 == 0 else '${colorB}' }}";
        brightness_pct = brightnessPct;
      };
    }
  ];
in {
  services.home-assistant.config."automation manual" = [
    {
      id = "wiz_front_lights_seasonal_on";
      alias = "Front WiZ lights: apply seasonal color on switch-on";
      description = "When the front entry circuit turns on, wait for the WiZ bulbs to rejoin Wi-Fi, set the always-white fixture to warm white, and apply the current season's color split to the other three.";
      mode = "single";
      trigger = [
        {
          platform = "state";
          entity_id = [frontSwitch];
          to = "on";
        }
      ];
      action = [
        {delay = postPowerOnDelay;}
        {
          service = "light.turn_on";
          target.entity_id = [frontWizWhite];
          data = {
            color_temp_kelvin = warmWhiteKelvin;
            brightness_pct = brightnessPct;
          };
        }
        (mkSeasonalChoose mkFrontSeasonalActions (frontWizA ++ frontWizB))
      ];
    }

    {
      id = "wiz_rear_light_seasonal_on";
      alias = "Rear WiZ light: apply seasonal color on switch-on";
      description = "When the patio circuit turns on, wait for the WiZ bulb to rejoin Wi-Fi, then apply the current season's color (alternating by day for a two-color season).";
      mode = "single";
      trigger = [
        {
          platform = "state";
          entity_id = [rearSwitch];
          to = "on";
        }
      ];
      action = [
        {delay = postPowerOnDelay;}
        (mkSeasonalChoose mkRearSeasonalActions [rearWiz])
      ];
    }

    {
      id = "wiz_lights_capture_last_state";
      alias = "WiZ lights: capture last commanded state";
      description = "Whenever a WiZ light settles into \"on\" (by the seasonal automations or a manual/app change), snapshot all five into one scene, so the most recent commanded state is always recoverable. Excludes the unavailable-to-on transition specifically so this never races with the reconnect-restore automation over the same event.";
      mode = "single";
      trigger = [
        {
          platform = "state";
          entity_id = allWizLights;
        }
      ];
      condition = [
        {
          condition = "template";
          value_template = "{{ trigger.to_state.state == 'on' and (trigger.from_state is none or trigger.from_state.state != 'unavailable') }}";
        }
      ];
      action = [
        {
          service = "scene.create";
          data = {
            scene_id = sceneId;
            snapshot_entities = allWizLights;
          };
        }
      ];
    }

    {
      id = "wiz_lights_restore_on_reconnect";
      alias = "WiZ lights: restore last state on unscheduled reconnect";
      description = "When a WiZ light comes back from unavailable while its backing switch has already been on for a while (an unscheduled reconnect, not the tail end of today's scheduled switch-on), restore the last snapshotted scene instead of leaving it at its own factory-default reset.";
      mode = "single";
      trigger = [
        {
          platform = "state";
          entity_id = allWizLights;
          from = "unavailable";
        }
      ];
      condition = [
        {
          # Maps the triggering light to its backing switch, then requires
          # that switch to have been "on" for well over the post-power-on
          # delay used by the scheduled-on automations above — this is what
          # distinguishes an unscheduled mid-window reconnect from the tail
          # end of a scheduled switch-on, which is also "switch on" moments
          # after automation A fires. Modeled on door-locks.nix's
          # last_changed-based hold-off.
          condition = "template";
          value_template = ''
            {% set switch_map = {
              '${frontWizWhite}': '${frontSwitch}',
              '${frontWizA1}': '${frontSwitch}',
              '${frontWizA2}': '${frontSwitch}',
              '${frontWizB1}': '${frontSwitch}',
              '${rearWiz}': '${rearSwitch}'
            } %}
            {% set sw = switch_map[trigger.entity_id] %}
            {{ is_state(sw, 'on') and (now() - states[sw].last_changed).total_seconds() > ${toString reconnectGraceSeconds} }}
          '';
        }
        {
          # Guards a reconnect happening before automation B has ever
          # captured anything (fresh HA restart, or before the first
          # light.turn_on) — scene.turn_on on a nonexistent scene would
          # otherwise fail this automation's run.
          condition = "template";
          value_template = "{{ states('${sceneEntity}') != 'unknown' }}";
        }
      ];
      action = [
        {
          service = "scene.turn_on";
          target.entity_id = [sceneEntity];
        }
      ];
    }
  ];
}
