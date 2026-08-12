# Single source of truth for hosts whose backrest UI is reverse-proxied
# cross-host by the fleet's Traefik host (currently reliant). Adding a host
# here is the only change needed to give it a backup-<name>.coppertop.ca
# route — its custom.dns.subdomains entry and custom.backups.backrest.
# proxiedRemotes entry are both derived from this list, so the two can't
# drift out of sync the way two independently hand-maintained lists can.
#
# Not derived from flake.nix's nixosConfigurations directly: that attrset
# only carries system/extraModules per host, and evaluating a sibling
# host's config from within another host's own modules is circular and not
# how this repo establishes cross-host awareness elsewhere (see
# lib/nas.nix, lib/ssh-hosts.nix — the same "plain data, not evaluated
# config" pattern). defiant is deliberately absent: its DNS/Traefik cutover
# to reliant is done and live, so nothing would ever resolve a route
# pointed at it (see docs/homelab-network.md § Migration: defiant →
# reliant). The Traefik host itself (reliant) is also absent — its own
# local instance is wired directly by custom.backups.backrest's subdomain
# default (backup-<hostName>), not through this list.
[
  {
    name = "enterprise-d";
    # Same LAN as the Traefik host; mDNS .local resolves across the link
    # (profiles/common/networking.nix's avahi). Dynamic IP-safe.
    url = "http://enterprise-d.local:9898";
  }
  {
    name = "holodeck-01";
    url = "http://holodeck-01.local:9898";
  }
  {
    name = "excelsior";
    # Different VLAN (192.168.1.x) from the Traefik host (192.168.20.x) —
    # link-local mDNS doesn't cross VLANs, so this is addressed by its
    # reserved static IP instead, same as the dns2 cross-VLAN route.
    url = "http://192.168.1.10:9898";
  }
]
