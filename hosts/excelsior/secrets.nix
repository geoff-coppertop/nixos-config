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

    # All three below are job-keyed, not machine-keyed (docs/secrets.md §
    # Secret Inventory) — each reuses an existing shared entry rather than
    # minting a new one. Every host mounts the same single NAS
    # (lib/nas.nix), so nas-smb-credentials needs no per-host distinction
    # either; the restic repo path already includes the hostname, so
    # sharing these doesn't collide backup data across hosts. The same
    # nas-smb-credentials entry also backs the /mnt/media CIFS mount in
    # media.nix — media/ is a subpath of the same share as backups/.
    "thomasga/nas-smb-credentials".file = ../../secrets/thomasga/nas-smb-credentials.age;
    "adguardhome/restic-password".file = ../../secrets/adguardhome/restic-password.age;
    "thomasga/restic-password".file = ../../secrets/thomasga/restic-password.age;
  };
}
