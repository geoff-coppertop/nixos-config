_: {
  age.secrets = {
    "thomasga/ssh-id-ed25519-excelsior" = {
      file = ../../secrets/thomasga/ssh-id-ed25519-excelsior.age;
      owner = "thomasga";
    };
    # Add further machine-specific secrets here (NAS, restic, etc.)
  };
}
