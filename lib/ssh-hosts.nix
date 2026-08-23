{
  enterprise-d = {
    aliases = ["enterprise-d"];
    # mDNS name (avahi publish is enabled in profiles/common/networking.nix);
    # the bare `enterprise-d` has no DNS record and never resolved.
    hostName = "enterprise-d.local";
    publicKey = null;
    user = "thomasga";
    userPublicKeys = {
      thomasga = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHsT6ghTWV7g27f97zFGPOqvRnnVBocLvL8BCD0QGxVG thomasga@enterprise-d";
    };
  };
  holodeck-01 = {
    aliases = ["holodeck-01"];
    # mDNS name. holodeck-01 is a WSL instance: this is the correct .local
    # name, but WSL2's NAT means it may not be reachable from other hosts —
    # it's normally rebuilt locally inside the distro rather than over SSH.
    hostName = "holodeck-01.local";
    publicKey = null;
    user = "thomasga";
    userPublicKeys = {
      thomasga = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKLdwIYeJFENvp95oViLvszT3v4/EK8dF5AIgCjDE+eT thomasga@holodeck-01";
    };
  };
  excelsior = {
    aliases = ["excelsior" "excelsior.local"];
    # mDNS name (avahi publish is enabled in profiles/common/networking.nix);
    # the bare `excelsior` has no DNS record and never resolved — same bug as
    # the other hosts, fixed the same way.
    hostName = "excelsior.local";
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHrIHWFlPQ9DIQGG5GrghyYAjmLMmPMQGzw+ML8uNpqr";
    user = "thomasga";
    userPublicKeys = {thomasga = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHuovWfG89BTyZhSeMd4av3Eizu8ynNvuxpq7j8+5ldS thomasga@excelsior";};
  };
  reliant = {
    aliases = ["reliant" "reliant.local"];
    # mDNS name (avahi publish is enabled in profiles/common/networking.nix);
    # the bare `reliant` has no DNS record and never resolved — same bug as
    # the other hosts, fixed the same way.
    hostName = "reliant.local";
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHR5Y3Q0/1GiR9iqqJK5C4pUY7CfXgo4qb7HFruMZgdz";
    user = "thomasga";
    userPublicKeys = {thomasga = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOmsSJjqOzYrowRUv5tz6xX6EYj5Gt7F2ml4Y8NKI7EW thomasga@reliant";};
  };
}
