# Home Assistant declarative config for defiant, organized one file per concern.
#
# Each imported file contributes to services.home-assistant.config — today
# automations under the "automation manual" key, and room to grow into that
# concern's helpers, scripts, or template sensors later. NixOS merges the
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
  ];
}
