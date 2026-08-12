_: {
  age.secrets = {
    "thomasga/nas-smb-credentials" = {
      file = ../../secrets/thomasga/nas-smb-credentials.age;
      owner = "thomasga";
    };
    "thomasga/restic-password".file =
      ../../secrets/thomasga/restic-password.age;
    "thomasga/backrest-admin-credentials".file =
      ../../secrets/thomasga/backrest-admin-credentials.age;
    "thomasga/ssh-id-ed25519-reliant" = {
      file = ../../secrets/thomasga/ssh-id-ed25519-reliant.age;
      owner = "thomasga";
    };

    # ── Phase 2: shared hardware/domain secrets, reused from defiant ─────
    # All four of these are named for what they hold or which physical
    # hardware they're tied to, not for either host (docs/secrets.md §
    # Shared hardware and domain secrets) — reliant is a rekeyed recipient,
    # plaintext content unchanged. Confirmed live: all four services using
    # them are up and working.

    # Cloudflare DNS-01 API token: just an API credential, not tied to
    # either host's identity — no reason to mint a second one.
    "traefik/cloudflare-api-token" = {
      file = ../../secrets/traefik/cloudflare-api-token.age;
      owner = "traefik";
    };

    # Same physical Zigbee coordinator as defiant's, once the dongle moves —
    # the network key is matched to the coordinator's own NVRAM state, not
    # the host, so reusing it (rather than generating a new one) is what
    # lets already-paired Zigbee devices keep working without a re-pair.
    "zigbee/network-key" = {
      file = ../../secrets/zigbee/network-key.age;
      owner = "zigbee2mqtt";
    };

    # Same home-address coordinates as defiant's — not host- or
    # radio-specific, safe to share outright.
    "location/coordinates".file = ../../secrets/location/coordinates.age;

    # Same physical Z-Wave controller as defiant's, once it moves — like the
    # Zigbee key above, Z-Wave securityKeys are matched to the controller's
    # own NVM state, not the host. Reusing them (instead of generating fresh
    # ones) is what avoids forcing an unnecessary re-pair of every Z-Wave
    # device once the controller relocates.
    "zwave/secrets" = {
      file = ../../secrets/zwave/secrets.age;
      owner = "zwave-js";
    };

    # restic-password secrets are job-keyed, not machine-keyed
    # (docs/secrets.md § Secret Inventory) — reusing defiant's existing
    # hass/zigbee2mqtt/zwave-js entries is the same pattern already used for
    # thomasga's home-dir backup job above. The restic repo path already
    # includes the hostname, so sharing the password doesn't collide the
    # two hosts' backup data. Attribute names match custom.backups.users'
    # entry names exactly, resolving to the module's default passwordFile
    # path with no override needed in configuration.nix.
    "hass/restic-password".file = ../../secrets/hass/restic-password.age;
    "zigbee2mqtt/restic-password".file =
      ../../secrets/zigbee2mqtt/restic-password.age;
    "zwave-js/restic-password".file =
      ../../secrets/zwave-js/restic-password.age;
    "adguardhome/restic-password".file =
      ../../secrets/adguardhome/restic-password.age;
  };
}
