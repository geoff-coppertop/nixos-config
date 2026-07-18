_: {
  age.secrets = {
    "thomasga/ssh-id-ed25519-defiant" = {
      file = ../../secrets/thomasga/ssh-id-ed25519-defiant.age;
      owner = "thomasga";
    };

    "defiant/cloudflare-api-token" = {
      file = ../../secrets/defiant/cloudflare-api-token.age;
      owner = "traefik";
    };

    "defiant/nas-smb-credentials".file = ../../secrets/defiant/nas-smb-credentials.age;

    # One restic-password secret per custom.backups.users entry — keyed to
    # the backup job's name, not the machine, since each entry gets its own
    # restic repo.
    "hass/restic-password".file = ../../secrets/hass/restic-password.age;
    "zigbee2mqtt/restic-password".file = ../../secrets/zigbee2mqtt/restic-password.age;
    "zwave-js/restic-password".file = ../../secrets/zwave-js/restic-password.age;
    "adguardhome/restic-password".file = ../../secrets/adguardhome/restic-password.age;

    "defiant/zigbee-network-key" = {
      file = ../../secrets/defiant/zigbee-network-key.age;
      owner = "zigbee2mqtt";
    };

    # LOCATION_LAT/LOCATION_LON, consumed via EnvironmentFile — read by
    # systemd itself (root) before the consuming service drops privileges,
    # so no owner override is needed the way zigbee-network-key's is.
    "defiant/location".file = ../../secrets/defiant/location.age;

    "defiant/zwave-secrets" = {
      file = ../../secrets/defiant/zwave-secrets.age;
      owner = "zwave-js";
    };
  };
}
