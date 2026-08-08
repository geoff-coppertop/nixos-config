_: {
  age.secrets = {
    "thomasga/nas-smb-credentials" = {
      file = ../../secrets/thomasga/nas-smb-credentials.age;
      owner = "thomasga";
    };
    "thomasga/restic-password".file =
      ../../secrets/thomasga/restic-password.age;
    "thomasga/ssh-id-ed25519-reliant" = {
      file = ../../secrets/thomasga/ssh-id-ed25519-reliant.age;
      owner = "thomasga";
    };
    # Add further machine-specific secrets here (service secrets) as Phase 2
    # work enables them.
  };
}
