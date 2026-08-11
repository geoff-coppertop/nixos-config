# Home Assistant automation for reliant: Sonos amps follow their paired Wiim
# receivers over line-in.
#
# One instance of this pattern per Sonos S1 Amp / Wiim receiver pair, built by
# mkSonosWiim from just the pair's room name. Add another pair by dropping a
# `{room = "...";}` entry into `pairs` below; nothing else changes.
#
# Each pair: switches its Sonos Amp to line-in as soon as its Wiim starts
# playing, and stops that Sonos Amp once its Wiim has been stopped (paused,
# idle, off, or standby) continuously for `offAfter` (10 minutes by default) —
# the `for` duration on the trigger means playback resuming within that window
# simply never lets the trigger fire, no separate cancel logic needed. The
# stop is additionally conditioned on the Sonos still being on line-in, so it
# won't cut off playback started manually from another source (Spotify, etc.).
#
# Each Wiim receiver's analog line-out feeds its paired Sonos Amp's line-in
# port; the Wiim is exposed to Home Assistant as a media_player entity by its
# own integration, and the Sonos Amp is bridged through Home Assistant's
# native Sonos integration.
#
# Real rooms/entity IDs, confirmed live against reliant's actual devices:
# media_player.wiim_<slug> / media_player.sonos_<slug> (not sonos_amp_<slug> —
# these Sonos Amp entities came out of pairing without "amp" in the
# entity_id, so the `sonos` default below matches that, not the more generic
# name a fresh pairing might produce). The Wiim's actual non-playing state
# values and the Sonos line-in source name are still unconfirmed — verify
# against Developer Tools > States before relying on the offAfter automation,
# and override `lineIn`/the trigger `to` list per pair if they differ from
# the defaults below ("Line-in", "paused"/"idle"/"off"/"standby").
#
# Targets reliant, not defiant — defiant is being retired (see
# hosts/reliant/README.md), and this automation never merged/deployed while
# defiant was still the live target, so there is no existing defiant state to
# carry over the way the other files in this directory note.
#
# Declared under the "automation manual" key (not bare "automation") so these
# coexist with any UI-created automations, matching
# services.home-assistant.configWritable = true. NixOS merges this list with the
# "automation manual" lists in the sibling files under this directory (see
# default.nix).
{lib, ...}: {
  services.home-assistant.config."automation manual" = let
    # Entity-safe id stem from a room name: lowercase, drop apostrophes/dots,
    # spaces to underscores. "Geoff's Office" -> "geoffs_office" (matching the
    # real slug presence-lighting.nix already uses for that room).
    sanitizeSlug = room: lib.replaceStrings [" " "'" "."] ["_" "" ""] (lib.toLower room);

    # Build both automations for one Sonos/Wiim pair from just its room name.
    # `slug`, `wiim`, and `sonos` all default off `room`/`slug` — correct as-is
    # if each device's entity_id is renamed to match (see the file header),
    # otherwise override `wiim`/`sonos` explicitly. `lineIn` is the Sonos
    # source name; `offAfter` is how long the Wiim must stay stopped before its
    # Sonos is stopped.
    mkSonosWiim = {
      room,
      slug ? sanitizeSlug room,
      wiim ? "media_player.wiim_${slug}",
      sonos ? "media_player.sonos_${slug}",
      lineIn ? "Line-in",
      offAfter ? "00:10:00",
    }: [
      {
        id = "sonos_line_in_on_wiim_play_${slug}";
        alias = "${room}: Sonos plays line-in when Wiim starts playing";
        description = "Switch ${room}'s Sonos Amp to its Wiim-fed line-in input when its Wiim starts playing.";
        mode = "single";
        trigger = [
          {
            platform = "state";
            entity_id = wiim;
            to = "playing";
          }
        ];
        action = [
          {
            service = "media_player.select_source";
            target.entity_id = [sonos];
            data.source = lineIn;
          }
          {
            # select_source switches the input but, confirmed live, doesn't
            # reliably start playback on its own -- the Sonos Amp sits on
            # line-in without audio until told to play.
            service = "media_player.media_play";
            target.entity_id = [sonos];
          }
        ];
      }
      {
        id = "sonos_off_after_wiim_stops_${slug}";
        alias = "${room}: Sonos stops line-in after Wiim stops";
        description = "Stop ${room}'s Sonos Amp once its Wiim has been stopped for ${offAfter}.";
        mode = "single";
        trigger = [
          {
            platform = "state";
            entity_id = wiim;
            to = ["paused" "idle" "off" "standby"];
            for = offAfter;
          }
        ];
        condition = [
          {
            condition = "state";
            entity_id = sonos;
            attribute = "source";
            state = lineIn;
          }
        ];
        action = [
          {
            service = "media_player.media_stop";
            target.entity_id = [sonos];
          }
        ];
      }
    ];
  in
    builtins.concatMap mkSonosWiim [
      {room = "Upper Living Room";}
      {room = "Master Bathroom";}
      {room = "Kitchen";}
      {room = "Patio";}
    ];
}
