{
  defiant = {
    aliases = ["defiant" "defiant.local"];
    hostName = "defiant";
    publicKey = null;
    user = "thomasga";
    userPublicKeys = {};
  };
  enterprise-d = {
    aliases = ["enterprise-d"];
    hostName = "enterprise-d";
    publicKey = null;
    user = "thomasga";
    userPublicKeys = {
      thomasga = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHsT6ghTWV7g27f97zFGPOqvRnnVBocLvL8BCD0QGxVG thomasga@enterprise-d";
    };
  };
  holodeck-01 = {
    aliases = ["holodeck-01"];
    hostName = "holodeck-01";
    publicKey = null;
    user = "thomasga";
    userPublicKeys = {
      thomasga = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKLdwIYeJFENvp95oViLvszT3v4/EK8dF5AIgCjDE+eT thomasga@holodeck-01";
    };
  };
  excelsior = {
    aliases = ["excelsior" "excelsior.local"];
    hostName = "excelsior";
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHrIHWFlPQ9DIQGG5GrghyYAjmLMmPMQGzw+ML8uNpqr";
    user = "thomasga";
    userPublicKeys = {thomasga = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHuovWfG89BTyZhSeMd4av3Eizu8ynNvuxpq7j8+5ldS thomasga@excelsior";};
  };
  reliant = {
    aliases = ["reliant" "reliant.local"];
    hostName = "reliant";
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHR5Y3Q0/1GiR9iqqJK5C4pUY7CfXgo4qb7HFruMZgdz";
    user = "thomasga";
    userPublicKeys = {thomasga = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOmsSJjqOzYrowRUv5tz6xX6EYj5Gt7F2ml4Y8NKI7EW thomasga@reliant";};
  };
  stargazer = {
    aliases = ["stargazer"];
    hostName = "stargazer";
    publicKey = null;
    user = "thomasga";
    # Populated after `nix develop -c python3 tools/enroll.py stargazer` and
    # generating the login key on the machine (see hosts/stargazer/README.md).
    userPublicKeys = {};
  };
}
