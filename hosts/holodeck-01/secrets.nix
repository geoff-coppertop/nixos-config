{
  age.secrets = {
    "thomasga/ssh-id-ed25519-holodeck-01" = {
      file = ../../secrets/thomasga/ssh-id-ed25519-holodeck-01.age;
      owner = "thomasga";
    };
    # The user's own personal NAS login. This host only ever runs the
    # thomasga home-dir backup job (no shared/appliance jobs), so it needs
    # this and nothing else for NAS backups — backup-svc is not a recipient
    # here. This host previously pointed its credentialsFile at
    # thomasga/nas-smb-credentials while declaring no age.secrets entry for
    # it and not being a recipient — so the file never existed at runtime and
    # backups here were silently broken. No owner: the backup mount is
    # performed by root.
    "thomasga/nas-smb-credentials".file =
      ../../secrets/thomasga/nas-smb-credentials.age;
    # Same gap as the NAS credential above: this host runs custom.backups
    # .users.thomasga (configuration.nix) but was never a recipient of the
    # restic password either, so the backup job's passwordFile never existed
    # at runtime. No owner: the backup mount is performed by root.
    "thomasga/restic-password".file =
      ../../secrets/thomasga/restic-password.age;
  };
}
