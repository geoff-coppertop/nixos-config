_: {
  age.secrets = {
    "thomasga/ssh-id-ed25519-excelsior" = {
      file = ../../secrets/thomasga/ssh-id-ed25519-excelsior.age;
      owner = "thomasga";
    };

    # New, excelsior-only secret — the restic repository password for the
    # dcs-server backup set.
    "dcs-server/restic-password".file = ../../secrets/dcs-server/restic-password.age;

    # Same shape as dcs-server above — excelsior-only restic repository
    # password for the factorio backup set. No owner: the backup service
    # runs as root.
    "factorio/restic-password".file = ../../secrets/factorio/restic-password.age;

    # The Factorio server's in-game join password, consumed by
    # services.factorio.extraSettingsFile. World-readable (0444, root-owned)
    # and deliberately so: services.factorio runs with DynamicUser = true, so
    # its UID does not exist yet when agenix decrypts secrets at activation
    # time and there is no static owner to chown to. excelsior has no local
    # accounts beyond the admin login. See docs/secrets.md § Factorio server
    # settings.
    "factorio/game-password" = {
      file = ../../secrets/factorio/game-password.age;
      mode = "0444";
    };

    # Two dedicated NAS service accounts, one per share, replacing the reused
    # personal thomasga login: backup-svc for the Backups share
    # (custom.backups.nas in configuration.nix) and media-svc for the Media
    # share (/mnt/media in media.nix). Each is ACL'd to its own share on the
    # NAS, so excelsior's Jellyfin mount can no longer reach backup data and
    # vice versa. No owner on either: both mounts are performed by root.
    "backup-svc/nas-smb-credentials".file = ../../secrets/backup-svc/nas-smb-credentials.age;
    "media-svc/nas-smb-credentials".file = ../../secrets/media-svc/nas-smb-credentials.age;

    # The user's own personal NAS login, for the thomasga home-dir backup job
    # only — that job keeps mounting Personal-Drive with the personal
    # credential via the per-entry NAS override, coexisting with backup-svc
    # above. The shared/appliance jobs (adguardhome, dcs-server, factorio)
    # stay on backup-svc. No owner: the mount is performed by root, matching
    # the two entries above.
    "thomasga/nas-smb-credentials".file = ../../secrets/thomasga/nas-smb-credentials.age;

    # Both restic-password entries below are job-keyed, not machine-keyed
    # (docs/secrets.md § Secret Inventory) — each reuses an existing shared
    # entry rather than minting a new one. The restic repo path already
    # includes the hostname, so sharing these doesn't collide backup data
    # across hosts.
    "adguardhome/restic-password".file = ../../secrets/adguardhome/restic-password.age;
    "thomasga/restic-password".file = ../../secrets/thomasga/restic-password.age;
  };
}
