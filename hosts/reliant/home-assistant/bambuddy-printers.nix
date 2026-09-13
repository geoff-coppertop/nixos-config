# Home Assistant entities for reliant: live telemetry from BambuBuddy
# (custom.bambuddy, modules/bambuddy.nix), the self-hosted Bambu Lab printer
# manager already running on this host.
#
# BambuBuddy does not send Home Assistant MQTT Discovery messages — confirmed
# directly against its `mqtt_relay.py` source, it publishes plain
# retained/non-retained JSON on plain topics only. Nothing shows up in HA on
# its own the way Zigbee2MQTT's bridge entities do (that one *does* speak
# discovery, which is why hosts/reliant/home-assistant has no equivalent file
# for it). So these entities are declared by hand here, against
# `services.home-assistant.config.mqtt` — the domain-level key for manually
# configured MQTT entities in current Home Assistant (the replacement for the
# deprecated per-platform `platform: mqtt` list under `sensor:`/
# `binary_sensor:`), not a new broker connection: HA's MQTT integration is
# already a config entry against this same broker (custom.mqtt, Mosquitto on
# 127.0.0.1:1883, "mqtt" already in extraComponents in
# hosts/reliant/configuration.nix), visible in the HA UI as the "localhost"
# MQTT service.
#
# One entry per physical printer in `printers` below, all entities generated
# from it by `mkPrinterEntities` and combined with `concatMap` — same
# mk*/map-over-a-list shape as sonos-wiim.nix's `mkSonosWiim`. A second
# printer (already anticipated) is just another `{ name = ...; serial =
# ...; }` element; nothing else in this file changes. `serial` is BambuBuddy's
# own topic key, confirmed live via `mosquitto_sub` against reliant's broker
# (not guessable from the printer's name):
#
#   bambuddy/printers/<serial>/status       - per-printer state, retained,
#                                             ~1/sec while connected
#   bambuddy/printers/<serial>/plate_clear  - "finished and still waiting for
#                                             someone to clear the bed" gate,
#                                             retained
#   bambuddy/status                         - BambuBuddy's own
#                                             online/offline, retained,
#                                             independent of any one printer
#
# `bambuddy/status` backs `availability` on every entity below (not just
# `bambuddy/printers/<serial>/status`'s own `connected` field, which becomes
# its own binary_sensor instead): idiomatic MQTT-sensor practice, so a printer
# reads "unavailable" if BambuBuddy itself goes down, distinct from the
# printer being reachably off/idle.
#
# Unverified assumption, not yet confirmed against a live print: `progress` is
# treated as already 0-100 (unit "%"), and `remaining_time` as minutes. The
# one real payload this was written against was captured with the printer
# IDLE, where both read 0 either way, so the scale couldn't be confirmed from
# it. Check both against Developer Tools > States mid-print and fix the
# `value_template`s (e.g. `progress * 100`) or `unit_of_measurement` here if
# wrong.
#
# The `mqtt:` schema used here (`sensor`/`binary_sensor` lists, each entity's
# own `availability` list, `device` grouping) is current at the time of
# writing but wasn't checked against a live instance or fetchable upstream
# docs in this session (outbound access to home-assistant.io was blocked from
# this sandbox) — same "Invalid config" failure mode as any other
# extraComponents/YAML mismatch described in docs/smart-home.md § Choosing
# extraComponents applies if this schema has drifted; check the HA log after
# first deploy.
{
  lib,
  config,
  ...
}: let
  inherit (lib) concatMap;

  # BambuBuddy's own availability, shared by every entity below regardless of
  # which printer it belongs to.
  serviceAvailability = [
    {
      topic = "bambuddy/status";
      value_template = "{{ value_json.status }}";
      payload_available = "online";
      payload_not_available = "offline";
    }
  ];

  printers = [
    {
      name = "P2S";
      serial = "22E8AJ5C1000983";
      # BambuBuddy's own internal DB row id, which its camera routes key on —
      # NOT derivable from `serial`, and BambuBuddy exposes no lookup between
      # the two. Read a second printer's id off its own working camera URL
      # (bambuddy.coppertop.ca/camera/<id>) the same way this one was.
      cameraId = 1;
    }
  ];

  # Builds every sensor/binary_sensor entity for one printer. `slug` defaults
  # off `name`, same sanitizeSlug shape as sonos-wiim.nix, and feeds both the
  # unique_id and the device grouping.
  mkPrinterEntities = {
    name,
    serial,
    cameraId,
    slug ? lib.toLower (lib.replaceStrings [" "] ["_"] name),
  }: let
    statusTopic = "bambuddy/printers/${serial}/status";
    plateClearTopic = "bambuddy/printers/${serial}/plate_clear";

    # Groups every entity below under one Home Assistant device page rather
    # than leaving them as unrelated loose entities.
    device = {
      identifiers = ["bambuddy_${slug}"];
      name = "${name} (BambuBuddy)";
      manufacturer = "Bambu Lab";
      model = name;
    };

    mkSensor = {
      id,
      label,
      valueTemplate,
      extra ? {},
    }:
      {
        name = "${name} ${label}";
        unique_id = "bambuddy_${slug}_${id}";
        state_topic = statusTopic;
        value_template = valueTemplate;
        availability = serviceAvailability;
        inherit device;
      }
      // extra;
  in {
    sensor = [
      (mkSensor {
        id = "state";
        label = "State";
        valueTemplate = "{{ value_json.state }}";
      })
      (mkSensor {
        id = "progress";
        label = "Progress";
        valueTemplate = "{{ value_json.progress }}";
        extra = {
          unit_of_measurement = "%";
          state_class = "measurement";
        };
      })
      (mkSensor {
        id = "remaining_time";
        label = "Remaining Time";
        valueTemplate = "{{ value_json.remaining_time }}";
        extra = {
          device_class = "duration";
          unit_of_measurement = "min";
          state_class = "measurement";
        };
      })
      (mkSensor {
        id = "layer";
        label = "Layer";
        valueTemplate = "{{ value_json.layer_num }}";
        extra.state_class = "measurement";
      })
      (mkSensor {
        id = "total_layers";
        label = "Total Layers";
        valueTemplate = "{{ value_json.total_layers }}";
        extra.state_class = "measurement";
      })
      (mkSensor {
        id = "nozzle_temperature";
        label = "Nozzle Temperature";
        valueTemplate = "{{ value_json.temperatures.nozzle }}";
        extra = {
          device_class = "temperature";
          unit_of_measurement = "°C";
          state_class = "measurement";
        };
      })
      (mkSensor {
        id = "nozzle_target_temperature";
        label = "Nozzle Target Temperature";
        valueTemplate = "{{ value_json.temperatures.nozzle_target }}";
        extra = {
          device_class = "temperature";
          unit_of_measurement = "°C";
          state_class = "measurement";
          entity_category = "diagnostic";
        };
      })
      (mkSensor {
        id = "bed_temperature";
        label = "Bed Temperature";
        valueTemplate = "{{ value_json.temperatures.bed }}";
        extra = {
          device_class = "temperature";
          unit_of_measurement = "°C";
          state_class = "measurement";
        };
      })
      (mkSensor {
        id = "bed_target_temperature";
        label = "Bed Target Temperature";
        valueTemplate = "{{ value_json.temperatures.bed_target }}";
        extra = {
          device_class = "temperature";
          unit_of_measurement = "°C";
          state_class = "measurement";
          entity_category = "diagnostic";
        };
      })
      (mkSensor {
        id = "chamber_temperature";
        label = "Chamber Temperature";
        valueTemplate = "{{ value_json.temperatures.chamber }}";
        extra = {
          device_class = "temperature";
          unit_of_measurement = "°C";
          state_class = "measurement";
        };
      })
      (mkSensor {
        id = "chamber_target_temperature";
        label = "Chamber Target Temperature";
        valueTemplate = "{{ value_json.temperatures.chamber_target }}";
        extra = {
          device_class = "temperature";
          unit_of_measurement = "°C";
          state_class = "measurement";
          entity_category = "diagnostic";
        };
      })
      (mkSensor {
        id = "wifi_signal";
        label = "Wi-Fi Signal";
        valueTemplate = "{{ value_json.wifi_signal }}";
        extra = {
          device_class = "signal_strength";
          unit_of_measurement = "dBm";
          state_class = "measurement";
          entity_category = "diagnostic";
        };
      })
    ];

    binary_sensor = [
      {
        name = "${name} Connected";
        unique_id = "bambuddy_${slug}_connected";
        state_topic = statusTopic;
        value_template = "{{ 'ON' if value_json.connected else 'OFF' }}";
        device_class = "connectivity";
        entity_category = "diagnostic";
        availability = serviceAvailability;
        inherit device;
      }
      {
        # BambuBuddy's own reason this topic exists (per its source
        # comments): distinguishing "finished" from "finished and still
        # waiting for someone to clear the bed" is not reliable from `state`
        # alone once Auto Off has stopped telemetry.
        name = "${name} Awaiting Plate Clear";
        unique_id = "bambuddy_${slug}_awaiting_plate_clear";
        state_topic = plateClearTopic;
        value_template = "{{ 'ON' if value_json.awaiting else 'OFF' }}";
        availability = serviceAvailability;
        inherit device;
      }
    ];

    # A refreshing still, not a live stream, and that is the deliberate half
    # of the trade — see the comment at the foot of this file. What buys it:
    # `unique_id`, which a legacy YAML camera platform cannot set, and which
    # is what puts the entity in Home Assistant's entity registry so it can
    # be assigned to an area and a device at all.
    image = [
      {
        name = "${name} Camera";
        unique_id = "bambuddy_${slug}_camera";
        # The timestamp is load-bearing, not cosmetic: a template image
        # re-fetches only when its `url` template evaluates to a new value
        # (template/image.py's _update_url clears the cached image on
        # change). A static URL would be fetched once and then never again,
        # which looks like a working entity showing a frozen frame.
        url = "http://127.0.0.1:${toString config.custom.bambuddy.port}/api/v1/printers/${toString cameraId}/camera/snapshot?t={{ now().timestamp() | int }}";
      }
    ];
  };

  perPrinter = map mkPrinterEntities printers;
in {
  services.home-assistant.config = {
    mqtt = {
      sensor = concatMap (p: p.sensor) perPrinter;
      binary_sensor = concatMap (p: p.binary_sensor) perPrinter;
    };

    # One trigger-based template block driving every printer's image. The
    # trigger is what sets the refresh rate: it re-evaluates the `url`
    # template, whose timestamp then differs, which is what makes Home
    # Assistant re-fetch. 10s is a deliberate floor on how hard a background
    # dashboard tile leans on the printer's own camera, since every fetch is
    # a real capture through BambuBuddy.
    template = [
      {
        trigger = [
          {
            platform = "time_pattern";
            seconds = "/10";
          }
        ];
        image = concatMap (p: p.image) perPrinter;
      }
    ];
  };

  # Camera notes, for whoever touches the `image` block above.
  #
  # BambuBuddy's camera API, confirmed straight from upstream's
  # backend/app/api/routes/camera.py (`v1.2.5.3`) — the router is mounted at
  # prefix "/printers" under the app's "/api/v1", hence both segments:
  #
  #   GET /api/v1/printers/{printer_id}/camera/stream?fps=<1-30>   (MJPEG)
  #   GET /api/v1/printers/{printer_id}/camera/snapshot            (JPEG)
  #
  # Neither needs a `?token=` here: both are gated by
  # `RequireCameraStreamTokenIfAuthEnabled`/its snapshot twin, which reduce to
  # a no-op while `is_auth_enabled()` is false — confirmed from
  # backend/app/core/auth.py, and false by default (no `auth_enabled` settings
  # row at all, not merely `false`). Turning BambuBuddy's own auth on in its UI
  # would start returning 401 here with no other symptom.
  #
  # Why a template `image` and not a `camera:` platform, which would give live
  # video instead of a still every 10s. Three platforms were tried, in order:
  #
  #   mjpeg / generic  Config-flow-only. Verified in each component's own
  #                    camera.py: `async_setup_entry` and nothing else, no
  #                    PLATFORM_SCHEMA, no YAML import flow. The NixOS module
  #                    can only write configuration.yaml, never a config
  #                    entry, so a `camera:` entry naming either passes schema
  #                    validation and then silently yields no entity and no
  #                    error at all.
  #   ffmpeg           Works, and gives a real live MJPEG feed. Ruled out
  #                    anyway: its PLATFORM_SCHEMA accepts only `input`,
  #                    `extra_arguments` and `name`, so the entity can never
  #                    carry a `unique_id`. Without one it never enters the
  #                    entity registry, and area and device assignment both
  #                    live in that registry — so it can never be put in an
  #                    area, attached to a device, or renamed from the UI.
  #                    This was deployed first and the limitation is real,
  #                    not theoretical: HA shows "this entity does not have a
  #                    unique ID, therefore its settings cannot be managed
  #                    from the UI".
  #   template image   What is used. `unique_id` is accepted, so the entity is
  #                    registry-backed and area-assignable. The cost is that
  #                    it is an image, not a camera: a still that refreshes at
  #                    the trigger interval, and it does not appear in
  #                    camera-specific pickers.
  #
  # If a live feed is ever wanted alongside this, add the MJPEG IP Camera
  # integration once through the UI — that route is a config entry, so it gets
  # a unique_id and an area *and* live video. It just cannot originate here.
  #
  # 127.0.0.1 is load-bearing, not incidental: Home Assistant runs on this
  # same host, custom.bambuddy.port is bound loopback-only
  # (custom.bambuddy.listenAddress) and deliberately not opened in the
  # firewall (Traefik-only), so any LAN-facing form of this URL hangs rather
  # than erroring — the host's firewall drops rather than rejects. Confirmed
  # live the hard way. The port is read from the option rather than hardcoded;
  # the address is not, because loopback is what HA must dial regardless of
  # what the service binds.
}
