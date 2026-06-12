_: {
  age.secrets = {
    # Secrets are created during provisioning and added here progressively.
    #
    # After running tools/enroll-machine.sh defiant, add:
    #   "thomasga/ssh-id-ed25519-defiant" = {
    #     file = ../../secrets/thomasga/ssh-id-ed25519-defiant.age;
    #     owner = "thomasga";
    #   };
    #
    # After creating secrets/defiant/cloudflare-api-token.age:
    #   "defiant/cloudflare-api-token" = {
    #     file = ../../secrets/defiant/cloudflare-api-token.age;
    #     owner = "traefik";
    #   };
    #
    # After creating secrets/defiant/nas-smb-credentials.age:
    #   "defiant/nas-smb-credentials".file = ../../secrets/defiant/nas-smb-credentials.age;
    #
    # After creating secrets/defiant/restic-password.age:
    #   "defiant/restic-password".file = ../../secrets/defiant/restic-password.age;
    #
    # After Phase 2 of provisioning (extract from first boot):
    #   "defiant/zigbee-network-key" = {
    #     file = ../../secrets/defiant/zigbee-network-key.age;
    #     owner = "zigbee2mqtt";
    #   };
    #   "defiant/syncthing-key" = {
    #     file = ../../secrets/defiant/syncthing-key.age;
    #     owner = "syncthing";
    #   };
    #   "defiant/syncthing-cert" = {
    #     file = ../../secrets/defiant/syncthing-cert.age;
    #     owner = "syncthing";
    #   };
    #   "defiant/zwave-secrets" = {
    #     file = ../../secrets/defiant/zwave-secrets.age;
    #     owner = "zwave-js";
    #   };
  };
}
