{
  age = {
    identityPaths = ["/var/lib/agenix/identity"];

    secrets = {
      "thomasga/nas-smb-credentials".file =
        ../secrets/thomasga/nas-smb-credentials.age;
      "thomasga/restic-password".file =
        ../secrets/thomasga/restic-password.age;
    };
  };
}
