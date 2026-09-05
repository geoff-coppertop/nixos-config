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

    # All three below are job-keyed, not machine-keyed (docs/secrets.md §
    # Secret Inventory) — each reuses an existing shared entry rather than
    # minting a new one. Every host mounts the same single NAS
    # (lib/nas.nix), so nas-smb-credentials needs no per-host distinction
    # either; the restic repo path already includes the hostname, so
    # sharing these doesn't collide backup data across hosts.
    "thomasga/nas-smb-credentials".file = ../../secrets/thomasga/nas-smb-credentials.age;
    "adguardhome/restic-password".file = ../../secrets/adguardhome/restic-password.age;
    "thomasga/restic-password".file = ../../secrets/thomasga/restic-password.age;
  };
}
