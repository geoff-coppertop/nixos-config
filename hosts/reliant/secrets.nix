_: {
  age.secrets = {
    # Dedicated NAS service account for the Backups share, used by the
    # shared/appliance backup jobs (hass, zigbee2mqtt, zwave-js,
    # adguardhome). No owner: the backup service runs as root, same as the
    # restic-password entries below.
    "backup-svc/nas-smb-credentials".file =
      ../../secrets/backup-svc/nas-smb-credentials.age;

    # The user's own personal NAS login, for the thomasga home-dir backup
    # job only — that job keeps mounting Personal-Drive with the personal
    # credential via the per-entry NAS override, coexisting with backup-svc
    # above on this host. No owner: the backup mount is performed by root,
    # matching backup-svc.
    "thomasga/nas-smb-credentials".file =
      ../../secrets/thomasga/nas-smb-credentials.age;
    "thomasga/restic-password".file =
      ../../secrets/thomasga/restic-password.age;
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

    # AQICN API token for the outdoor-AQI REST sensor
    # (home-assistant/outdoor-aqi.nix) — owned by hass so that service's own
    # preStart (which runs as hass) can read it directly and write it into
    # HA's secrets.yaml, no root step needed.
    "hass/aqicn-token" = {
      file = ../../secrets/hass/aqicn-token.age;
      owner = "hass";
    };

    # ── lldap + Authelia SSO stack ───────────────────────────────────────
    # All brand new, none reused from defiant. Owner is set only where the
    # consuming process actually reads the file as a non-root user: every
    # entry without an owner is read either by root itself (restic, systemd's
    # own EnvironmentFile/LoadCredential handling) or copied in by systemd
    # before the service drops privileges.

    # lldap runs as its own static "lldap" system user (nixpkgs'
    # services.lldap, not DynamicUser), and the server reads both of these
    # itself at startup — ldap_user_pass_file and jwt_secret_file are plain
    # paths in its own config, not systemd credentials.
    "lldap/admin-password" = {
      file = ../../secrets/lldap/admin-password.age;
      owner = "lldap";
    };
    "lldap/jwt-secret" = {
      file = ../../secrets/lldap/jwt-secret.age;
      owner = "lldap";
    };

    # No owner: these two go through nixpkgs'
    # services.authelia.instances.main.secrets.*, which wires them up as
    # systemd LoadCredential entries. systemd performs that copy as root
    # during unit setup, before authelia-main is assumed, so root-only
    # (agenix' default 0400 root:root) is both sufficient and the narrower
    # choice — see modules/authelia.nix's environmentVariables comment for
    # the contrast with ldap-bind-password below.
    "authelia/jwt-secret".file = ../../secrets/authelia/jwt-secret.age;
    "authelia/storage-encryption-key".file =
      ../../secrets/authelia/storage-encryption-key.age;

    # Owner authelia-main: this one is NOT a LoadCredential secret. It is
    # handed to Authelia as a raw path in
    # AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD_FILE, so the file itself
    # must be readable by the instance's own system user. Its second
    # consumer — custom.lldap.bootstrap.users' "authelia" entry's
    # passwordFile — is read by lldap-bootstrap.service, which runs as root
    # and so is unaffected by the owner. One file on purpose: lldap and
    # Authelia must never disagree about this credential.
    "authelia/ldap-bind-password" = {
      file = ../../secrets/authelia/ldap-bind-password.age;
      owner = "authelia-main";
    };

    # Same job-keyed restic pattern as the entries above; attribute names
    # match custom.backups.users.lldap / .authelia exactly, so the module's
    # default passwordFile path resolves with no override. No owner —
    # backups run as root.
    "lldap/restic-password".file = ../../secrets/lldap/restic-password.age;
    "authelia/restic-password".file =
      ../../secrets/authelia/restic-password.age;

    # Authelia's OIDC provider. Both of these are LoadCredential-backed
    # (secrets.oidcIssuerPrivateKeyFile / secrets.oidcHmacSecretFile), same
    # reasoning as jwt-secret above — no owner needed.
    "authelia/oidc-issuer-private-key".file =
      ../../secrets/authelia/oidc-issuer-private-key.age;
    "authelia/oidc-hmac-secret".file =
      ../../secrets/authelia/oidc-hmac-secret.age;

    # Owner authelia-main: read directly by Authelia's own Go-template
    # "secret" function from the generated OIDC client settingsFile, not via
    # LoadCredential — same direct-read situation as ldap-bind-password.
    # Holds only the pbkdf2-sha512 digest, never the raw client secret.
    "authelia/oidc-client-secret-home-assistant-hash" = {
      file = ../../secrets/authelia/oidc-client-secret-home-assistant-hash.age;
      owner = "authelia-main";
    };

    # The raw half of that same client secret, for Home Assistant's side of
    # the OIDC handshake. No owner: consumed as a systemd EnvironmentFile,
    # which systemd reads as root before home-assistant.service's own
    # user/sandboxing applies — identical pattern to location/coordinates
    # above, and its contents are the same KEY=VALUE shape
    # (HASS_OIDC_CLIENT_SECRET=...).
    "home-assistant/oidc-client-secret".file =
      ../../secrets/home-assistant/oidc-client-secret.age;
  };
}
