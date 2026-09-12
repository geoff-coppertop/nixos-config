# Home Assistant automation for reliant: office AV receiver + projector power
# follows the office Apple TV.
#
# Powers the receiver and projector on when the office Apple TV wakes (goes
# from off/standby to an active playback state), and powers them off once the
# Apple TV has been off/standby continuously for 10 minutes — the `for` on the
# power-off trigger means turning the Apple TV back on inside that window
# simply cancels the pending automation run, no extra logic needed.
#
# Physical chain: Apple TV -> receiver (Yamaha HTR-4063) -> projector, all via
# HDMI. The Apple TV is exposed to Home Assistant by the `apple_tv` component
# (pyatv), already in hosts/reliant/configuration.nix's extraComponents and
# paired per hosts/reliant/README.md § Device Pairing Notes. Power commands
# reach the receiver and projector as IR bursts from a Broadlink RM4 mini,
# exposed by the `broadlink` component, also already in extraComponents,
# paired via the HA UI as remote.geoff_s_office_wi_fi_universal_remote
# (Broadlink markets the RM4 mini as a "Wi-Fi IR/RF Universal Remote", hence
# the HA-derived entity id from that name).
#
# Both devices' commands are captured via HA's remote.learn_command and then
# copied out of live storage into the four *Code constants below, rather than
# referenced by device/command name — deliberately, so this file is fully
# reproducible from git alone. A device/command name (`data = { device =
# "projector"; command = "PowerOn"; }`) only resolves against whatever's been
# learned into the RM4's own .storage on the running instance; that state
# isn't declared anywhere, so a fresh Home Assistant instance (a reinstall, a
# lost /var/lib/hass) would silently have a broken automation until someone
# remembered to manually re-learn all four commands. Baking the raw codes in
# here instead means the automation works immediately on any instance this
# config is applied to, matching this repo's everything-declarative posture.
#
# The projector's remote has discrete Power On / Standby buttons, so its two
# captures (epsonPowerliteHomeCinema3020PowerOnCode/
# epsonPowerliteHomeCinema3020PowerOffCode) are exactly what
# remote.learn_command recorded, no decoding needed.
#
# The receiver's remote has only a single power TOGGLE button — no discrete
# on/off to learn directly. Confirmed live: its NEC command table has genuine
# discrete codes anyway (address 0x7E; ON = 0x7E, STANDBY = 0x7F), which the
# stock remote just never exposes a button for. Decoded from a learned
# capture of the toggle button (address + ~address bytes, verified via NEC's
# byte/complement checksum), cross-referenced against a known Yamaha RX-V
# code table for the same address, then synthesized as raw NEC frames reusing
# the unit's own captured timing and tested directly against the hardware:
# sent while off -> turned on; sent while on -> turned off and, sent again,
# stayed off (ruling out a second toggle). yamahaHtr4063PowerOnCode/
# yamahaHtr4063PowerOffCode below are therefore synthesized, not a raw
# remote.learn_command capture like the projector's — everything else about
# how they're sent is identical.
#
# Why this goes through IR instead of CEC: confirmed live, CEC already handles
# volume correctly for this setup (Apple TV Settings > Remotes and Devices >
# Volume Control > Auto, with HDMI Control enabled on the receiver) — that
# needs no Home Assistant or Nix config at all. But confirmed live, CEC does
# NOT cascade power here: putting the Apple TV to sleep does not power off the
# receiver or projector, even though the Apple TV is CEC-wired directly to the
# receiver rather than passing through the projector — so it isn't a
# pass-through gap, CEC power simply doesn't propagate on this hardware. Hence
# power is driven explicitly through the Broadlink RM4 via these two
# automations instead.
#
# Entity IDs used here: media_player.apple_tv_geoff_s_office and
# remote.geoff_s_office_wi_fi_universal_remote (both confirmed against the
# live entity registry).
#
# Declared under the "automation manual" key (not bare "automation") so these
# coexist with any UI-created automations, matching
# services.home-assistant.configWritable = true. NixOS merges this list with
# the "automation manual" lists in the sibling files under this directory (see
# default.nix).
let
  # Raw Broadlink codes for the projector's two discrete power commands, as
  # captured directly by remote.learn_command against its real remote (see
  # header comment above for why these are baked in rather than referenced
  # by device/command name).
  epsonPowerliteHomeCinema3020PowerOnCode = "b64:JgDYAAABJZIUNRI3FBESEhMSExIVEBM2FDUUERQ1EhMTNhITEjcUERQREhIVEBMSEzYUERMSEzYSNxQ1EjcUNRQREjYUNRUQEwAFNwABJpIVNBM2FBEUERMSFBETEhI3FDUUERQ0FRAVNBMSEzYUERQRExIUERITFDUUERISFTQVNBU0FTQVNhMQEzYUNRQRFAAFNQABJpIVNBM2ExITEhQRExIUERI3FDUUERI2FRAVNBUQFTQUERMSExIUERITEzYSExISEzYVNBM2EzYVNBUQEzYUNRMSFAANBQ==";
  epsonPowerliteHomeCinema3020PowerOffCode = "b64:JgCQAAABJJIUNRQ1FBEUERQRFBEUERQ0FTQVEBU0FRAVNBQRFDUUERQ1FBEUERQRFDUUEBUQFTQVEBQ1FDUUNRQRFDUSNxQREgAFNwABKJESNxI3EhMSEhMSExITEhM2EzYTEhI3ExIUNRQRFDUSEhU0FRAVEBQREzYUERQRFDUUERI3EjcSNxQQFTQTNhMSEwANBQ==";

  # Raw Broadlink NEC codes for the receiver's discrete power commands (see
  # header comment above for how these were derived and confirmed). Reuses
  # the receiver's own captured pulse timing and address bits; only the NEC
  # command byte differs between the two (0x7E vs 0x7F).
  yamahaHtr4063PowerOnCode = "b64:JgBFAAABJJMUERM3EzcSNxM3EzcSNxMSEzcTEhMSExISExISExITNxMSEzcTNxM3EzcTNxM3ExITNxMSExITEhMSExITEhM3FA==";
  yamahaHtr4063PowerOffCode = "b64:JgBFAAABJJMUERM3EzcSNxM3EzcSNxMSEzcTEhMSExISExISExITNxM3EzcTNxM3EzcTNxM3ExITEhMSExITEhMSExITEhM3FA==";
in {
  services.home-assistant.config."automation manual" = [
    {
      id = "appletv_office_power_on_av";
      alias = "Office AV: receiver + projector power on with Apple TV";
      description = "Power on the office receiver and projector via Broadlink IR when the office Apple TV wakes.";
      mode = "single";
      trigger = [
        {
          platform = "state";
          entity_id = "media_player.apple_tv_geoff_s_office";
          to = ["idle" "playing" "paused" "on"];
        }
      ];
      action = [
        {
          service = "remote.send_command";
          target.entity_id = ["remote.geoff_s_office_wi_fi_universal_remote"];
          data.command = epsonPowerliteHomeCinema3020PowerOnCode;
        }
        {
          # Stagger the two sends so both IR bursts from the one RM4 blaster
          # don't collide.
          delay = "00:00:01";
        }
        {
          service = "remote.send_command";
          target.entity_id = ["remote.geoff_s_office_wi_fi_universal_remote"];
          data.command = yamahaHtr4063PowerOnCode;
        }
      ];
    }
    {
      id = "appletv_office_power_off_av";
      alias = "Office AV: receiver + projector power off with Apple TV";
      description = "Power off the office receiver and projector via Broadlink IR once the office Apple TV has been off/standby for 10 minutes.";
      mode = "single";
      trigger = [
        {
          platform = "state";
          entity_id = "media_player.apple_tv_geoff_s_office";
          to = ["off" "standby"];
          for = "00:10:00";
        }
      ];
      action = [
        {
          service = "remote.send_command";
          target.entity_id = ["remote.geoff_s_office_wi_fi_universal_remote"];
          data.command = epsonPowerliteHomeCinema3020PowerOffCode;
        }
        {
          # Stagger the two sends so both IR bursts from the one RM4 blaster
          # don't collide.
          delay = "00:00:01";
        }
        {
          service = "remote.send_command";
          target.entity_id = ["remote.geoff_s_office_wi_fi_universal_remote"];
          data.command = yamahaHtr4063PowerOffCode;
        }
      ];
    }
  ];
}
