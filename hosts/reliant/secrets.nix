_: {
  age.secrets = {
    "thomasga/ssh-id-ed25519-reliant" = {
      file = ../../secrets/thomasga/ssh-id-ed25519-reliant.age;
      owner = "thomasga";
    };
    # Add further machine-specific secrets here (NAS, restic, service
    # secrets) as Phase 2 work enables them.
  };
}
