{
  age.secrets = {
    # The user's own personal NAS login. Two personal uses here: the
    # personal-drive desktop mount (custom.networkDrives) and the thomasga
    # home-dir backup job, which keeps mounting Personal-Drive with this
    # credential via the per-entry NAS override. Owned by thomasga for the
    # desktop mount; root can read it regardless for the backup mount.
    "thomasga/nas-smb-credentials" = {
      file = ../../secrets/thomasga/nas-smb-credentials.age;
      owner = "thomasga";
    };

    "thomasga/restic-password".file =
      ../../secrets/thomasga/restic-password.age;
    "thomasga/ssh-id-ed25519-enterprise-d" = {
      file = ../../secrets/thomasga/ssh-id-ed25519-enterprise-d.age;
      owner = "thomasga";
    };
    "thomasga/github-token" = {
      file = ../../secrets/thomasga/github-token.age;
      owner = "thomasga";
    };
    "thomasga/garmin-username" = {
      file = ../../secrets/thomasga/garmin-username.age;
      owner = "thomasga";
    };
    "thomasga/garmin-password" = {
      file = ../../secrets/thomasga/garmin-password.age;
      owner = "thomasga";
    };
  };
}
