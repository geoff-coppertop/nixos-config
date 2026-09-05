let
  enterprise-d = "age1nyd5azds343tn30m23x3ecmua9nfe04zhcrd7gq8qfp52kxk8a6snznw9l";

  holodeck-01 = "age1v6sv24jgrpdfex74d4d9xf92dpfy228lxmled4y4505py6ec7ghq4kmxz0";

  # Replace this with a distinct offline recovery key before expanding the fleet.
  excelsior = "age133y2ha4g4qa8esa52jp7k99xhqxm05m5q8yj909xynsv9ncv53xqfwyrgw";

  reliant = "age1lqu53gj7uyp6t98avjh25736kcl0a8devzgfepag5j5l4fkmvq7scs5y9w";

  offlineAdmin = "age135v2shcv64lul85dy5qqpwlnqw4rvdcsukymx63neqp37d9hpe0sp2jzp9";
in {
  # Job-keyed, not machine-keyed: every host running the "thomasga" backup job
  # is a recipient. The restic repo path already disambiguates by hostname.
  # excelsior is a recipient too — its home dir is backed up for consistency
  # with the rest of the fleet even though it's rarely used directly.
  # excelsior is also a recipient of both: its home dir is backed up for
  # consistency with the rest of the fleet, and it mounts the same NAS
  # (lib/nas.nix) so the SMB credential needs no per-host distinction.
  "thomasga/restic-password.age".publicKeys = [enterprise-d reliant excelsior offlineAdmin];
  "thomasga/nas-smb-credentials.age".publicKeys = [enterprise-d reliant excelsior offlineAdmin];
  "thomasga/ssh-id-ed25519-enterprise-d.age".publicKeys = [enterprise-d offlineAdmin];
  "thomasga/github-token.age".publicKeys = [enterprise-d offlineAdmin];
  "thomasga/garmin-username.age".publicKeys = [enterprise-d offlineAdmin];
  "thomasga/garmin-password.age".publicKeys = [enterprise-d offlineAdmin];
  "wifi/agt-home.age".publicKeys = [enterprise-d offlineAdmin];
  "wifi/agt-iot.age".publicKeys = [enterprise-d offlineAdmin];
  "wifi/agt-work.age".publicKeys = [enterprise-d offlineAdmin];
  "thomasga/ssh-id-ed25519-holodeck-01.age".publicKeys = [holodeck-01 offlineAdmin];
  # Just an API credential, not tied to any host's identity — named for what
  # consumes it (Traefik's ACME DNS-01), not the host, so any future host
  # running Traefik can be added as a recipient without a rename.
  "traefik/cloudflare-api-token.age".publicKeys = [reliant offlineAdmin];
  # Job-keyed, not machine-keyed, same reasoning as thomasga's above — the
  # restic repo path already disambiguates by hostname.
  "hass/restic-password.age".publicKeys = [reliant offlineAdmin];
  "zigbee2mqtt/restic-password.age".publicKeys = [reliant offlineAdmin];
  "zwave-js/restic-password.age".publicKeys = [reliant offlineAdmin];
  # excelsior added as a third recipient — it runs its own independent
  # AdGuard Home instance (the dns2 pair to reliant's), backed up the same
  # way reliant's is.
  "adguardhome/restic-password.age".publicKeys = [reliant excelsior offlineAdmin];
  # Matched to the physical Zigbee coordinator's own NVRAM state, not the
  # host — named for the hardware, not reliant, so it keeps working without
  # a rename if the coordinator moves again.
  "zigbee/network-key.age".publicKeys = [reliant offlineAdmin];
  # Shared receiver/station location (lat/lon/elevation) — used by adsb
  # (lat/lon only) and, on reliant, Home Assistant's core location config
  # (all three — see docs/smart-home.md § Core location). Not host- or
  # radio-specific.
  "location/coordinates.age".publicKeys = [reliant offlineAdmin];
  # Matched to the physical Z-Wave controller's own NVM state, not the
  # host — same reasoning as zigbee/network-key.age above.
  "zwave/secrets.age".publicKeys = [reliant offlineAdmin];
  "thomasga/ssh-id-ed25519-excelsior.age".publicKeys = [excelsior offlineAdmin];
  "thomasga/ssh-id-ed25519-reliant.age".publicKeys = [reliant offlineAdmin];
  "dcs-server/restic-password.age".publicKeys = [excelsior offlineAdmin];
  # Same job-keyed pattern as dcs-server above — excelsior is the only host
  # running the Factorio dedicated server.
  "factorio/restic-password.age".publicKeys = [excelsior offlineAdmin];
  # AQICN API token for the outdoor-AQI REST sensor in
  # hosts/reliant/home-assistant/climate-dashboard.nix — reliant only, not
  # shared with defiant like the hass/* secrets above, since reliant is the
  # only host running this integration.
  "hass/aqicn-token.age".publicKeys = [reliant offlineAdmin];
}
