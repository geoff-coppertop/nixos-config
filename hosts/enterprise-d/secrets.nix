{
  age.secrets = {
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
  };
}
