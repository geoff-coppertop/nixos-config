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
    # Uncomment together with custom.backups.users.syncthing in
    # ./configuration.nix once the secret exists:
    #   "syncthing/restic-password".file = ../../secrets/syncthing/restic-password.age;

    # Added after Phase 2 of provisioning (extract from first boot):
    #   "defiant/zigbee-network-key" = {
    #     file = ../../secrets/defiant/zigbee-network-key.age;
    #     owner = "zigbee2mqtt";
    #   };
    #   "defiant/zwave-secrets" = {
    #     file = ../../secrets/defiant/zwave-secrets.age;
    #     owner = "zwave-js";
    #   };
  };
}
