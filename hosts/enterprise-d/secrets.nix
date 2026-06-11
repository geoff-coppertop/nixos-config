{lib, ...}: {
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

  # Only deployed once the .age file has been created with:
  #   nix run .#secret-edit -- secrets/thomasga/obsidian-api-key.age
  age.secrets."thomasga/obsidian-api-key" = lib.mkIf (builtins.pathExists ../../secrets/thomasga/obsidian-api-key.age) {
    file = ../../secrets/thomasga/obsidian-api-key.age;
    owner = "thomasga";
  };
}
