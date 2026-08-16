# Home Assistant declarative config for reliant, organized one file per
# concern.
#
# outside-lights.nix/door-locks.nix/presence-lighting.nix/sonos-wiim.nix were
# copied verbatim from hosts/defiant/home-assistant/ as part of the Phase 2
# appliance-layer migration (see docs/provisioning.md § Two Phases) — those
# automations reference the same physical devices and entity IDs Home
# Assistant assigned on defiant, since it is the same Home Assistant
# instance (restored from defiant's backup) moving hosts, not a fresh one.
# Re-verify every entity ID against the running instance after the first
# activation on this host regardless — see docs/smart-home.md.
#
# ecobee-climate.nix is new, not part of that migration — the ecobee
# thermostats were never paired on defiant, so it targets reliant directly.
#
# Each imported file contributes to services.home-assistant.config today
# under the "automation manual" key, and room to grow into that concern's
# helpers, scripts, or template sensors later. NixOS merges the
# contributions together (the "automation manual" lists concatenate).
#
# This directory holds only per-concern automation/config content. The Home
# Assistant *service* itself — the package, extraComponents, HTTP/proxy setup —
# is configured by the reusable module at modules/home-assistant.nix
# (custom.home-assistant) plus the host's extraComponents in configuration.nix.
#
# To add an automation area: drop a new <concern>.nix file here and import it
# below.
{
  imports = [
    ./outside-lights.nix
    ./door-locks.nix
    ./presence-lighting.nix
    ./sonos-wiim.nix
    ./ecobee-climate.nix
    ./climate-dashboard.nix
    ./outdoor-aqi.nix
    ./kids-wake-lights.nix
  ];
}
