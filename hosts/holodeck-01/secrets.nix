{
  age.secrets = {
    "thomasga/ssh-id-ed25519-holodeck-01" = {
      file = ../../secrets/thomasga/ssh-id-ed25519-holodeck-01.age;
      owner = "thomasga";
    };
    "thomasga/backrest-admin-credentials".file =
      ../../secrets/thomasga/backrest-admin-credentials.age;
    # Add further machine-specific secrets here (NAS, restic, etc.)
  };
}
