# Outdoor air quality for the Climate dashboard, via the AQICN HTTP API
# directly rather than Home Assistant's native "waqi" integration — that
# integration is config_flow-only (CONFIG_SCHEMA =
# cv.config_entry_only_config_schema, confirmed against its source), with no
# YAML path at all, so it can't be declared here and its token has no way to
# come from agenix. A generic REST sensor against the same underlying API
# sidesteps both: fully declarative, and the token stays in agenix instead
# of living only in HA's UI-only integration storage.
#
# geo coordinates come from zone.home (already used for presence elsewhere
# under hosts/reliant/home-assistant/), not a hardcoded lat/lon or the
# shared location/coordinates.age secret — one less thing to keep in sync if
# the zone's location ever changes.
#
# The token can't be spliced into resource_template as
# "...token=!secret aqicn_token": confirmed against the rest integration's
# schema that "!secret" replaces an entire YAML scalar, not part of a larger
# string. It's a separate params.token instead — rest's params values are
# templates (cv.template), but a plain string with no Jinja syntax just
# renders back to itself once !secret substitutes the real token in.
#
# !secret resolves from secrets.yaml in HA's own config directory, which
# nothing populates by default. hass/aqicn-token.age (docs/secrets.md) is
# owned by the hass user, so this preStart — which runs as hass, same as
# the rest of the service, per the upstream module's hardcoded User/Group —
# can read it directly and write secrets.yaml itself. No placeholder+sed
# substitution needed here, unlike modules/zigbee.nix's network key: that
# one has no secrets-file mechanism of its own to hook into, but HA's
# "!secret" tag is exactly that mechanism.
{
  config,
  pkgs,
  ...
}: {
  services.home-assistant.config.rest = [
    {
      resource_template = "https://api.waqi.info/feed/geo:{{ state_attr('zone.home', 'latitude') }};{{ state_attr('zone.home', 'longitude') }}/";
      params.token = "!secret aqicn_token";
      scan_interval = "01:00:00";
      sensor = [
        {
          name = "Outdoor AQI";
          unique_id = "outdoor_aqi";
          value_template = "{{ value_json.data.aqi }}";
        }
      ];
    }
  ];

  # Writes secrets.yaml itself every start — the rest of this file's config
  # is the only consumer of any HA "!secret", so there's no existing file to
  # merge with or clobber.
  systemd.services.home-assistant.preStart = ''
    ${pkgs.coreutils}/bin/install -m 600 /dev/null "${config.services.home-assistant.configDir}/secrets.yaml"
    printf 'aqicn_token: %s\n' "$(${pkgs.coreutils}/bin/cat ${config.age.secrets."hass/aqicn-token".path})" > "${config.services.home-assistant.configDir}/secrets.yaml"
  '';
}
