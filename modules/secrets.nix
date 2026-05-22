{
  age = {
    identityPaths = ["/var/lib/agenix/identity"];
    secrets = {
      "thomasga/nas-smb-credentials".file =
        ../secrets/thomasga/nas-smb-credentials.age;
      "thomasga/restic-password".file =
        ../secrets/thomasga/restic-password.age;
      "thomasga/ssh-id-ed25519" = {
        file = ../secrets/thomasga/ssh-id-ed25519.age;
        owner = "thomasga";
      };
      "wifi/agt-home".file = ../secrets/wifi/agt-home.age;
      "wifi/agt-iot".file = ../secrets/wifi/agt-iot.age;
      "wifi/agt-work".file = ../secrets/wifi/agt-work.age;
    };
  };
}
