# Single source of truth for the internal coppertop.ca DNS zone.
#
# Every resolver serves this complete set, so any one of them can answer for
# the whole zone on its own. That is what makes the two AdGuard/unbound
# instances real redundancy: clients receive both resolvers via DHCP, and
# either alone resolves everything.
let
  # LAN IPs of the hosts that serve internal services (behind their Traefik).
  hosts = {
    defiant = "192.168.20.10";
    excelsior = "192.168.1.10";
  };
in {
  inherit hosts;

  # subdomain -> IP of the host whose Traefik serves it.
  records = {
    home = hosts.defiant; # Home Assistant
    dns1 = hosts.defiant; # defiant AdGuard admin UI
    dns2 = hosts.excelsior; # excelsior AdGuard admin UI, served by excelsior's own Traefik
    adsb = hosts.defiant; # ADS-B
    zigbee = hosts.defiant; # Zigbee2MQTT
    jellyfin = hosts.excelsior;
    arm = hosts.excelsior; # Automatic Ripping Machine
    tmm = hosts.excelsior; # tinyMediaManager
  };

  # Bare apex (coppertop.ca landing page).
  apex = hosts.defiant;
}
