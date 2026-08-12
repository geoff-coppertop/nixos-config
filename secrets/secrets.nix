let
  enterprise-d = "age1nyd5azds343tn30m23x3ecmua9nfe04zhcrd7gq8qfp52kxk8a6snznw9l";

  holodeck-01 = "age1v6sv24jgrpdfex74d4d9xf92dpfy228lxmled4y4505py6ec7ghq4kmxz0";

  # defiant age public key — populated by: nix develop -c python3 tools/enroll.py defiant
  defiant = "age18yumsydkuuz54uvj8rnxpehpnse6eduvghdcsf7pgc0pylywwg2s6yv6xr";

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
  # Every host running custom.backups.backrest is a recipient — one shared
  # admin login across all four instances, same sharing pattern (and same
  # follow-up caveat about splitting into per-machine credentials some day)
  # as thomasga/nas-smb-credentials.age above.
  "thomasga/backrest-admin-credentials.age".publicKeys = [enterprise-d reliant excelsior holodeck-01 offlineAdmin];
  "thomasga/ssh-id-ed25519-enterprise-d.age".publicKeys = [enterprise-d offlineAdmin];
  "thomasga/github-token.age".publicKeys = [enterprise-d offlineAdmin];
  "thomasga/garmin-username.age".publicKeys = [enterprise-d offlineAdmin];
  "thomasga/garmin-password.age".publicKeys = [enterprise-d offlineAdmin];
  "wifi/agt-home.age".publicKeys = [enterprise-d offlineAdmin];
  "wifi/agt-iot.age".publicKeys = [enterprise-d offlineAdmin];
  "wifi/agt-work.age".publicKeys = [enterprise-d offlineAdmin];
  "thomasga/ssh-id-ed25519-holodeck-01.age".publicKeys = [holodeck-01 offlineAdmin];
  "thomasga/ssh-id-ed25519-defiant.age".publicKeys = [defiant offlineAdmin];
  # Just an API credential, not tied to either host's identity — named for
  # what consumes it (Traefik's ACME DNS-01), not the host, so any future
  # host running Traefik can be added as a recipient without a rename.
  "traefik/cloudflare-api-token.age".publicKeys = [defiant reliant offlineAdmin];
  "defiant/nas-smb-credentials.age".publicKeys = [defiant offlineAdmin];
  # Job-keyed, not machine-keyed, same reasoning as thomasga's above — the
  # restic repo path already disambiguates by hostname.
  "hass/restic-password.age".publicKeys = [defiant reliant offlineAdmin];
  "zigbee2mqtt/restic-password.age".publicKeys = [defiant reliant offlineAdmin];
  "zwave-js/restic-password.age".publicKeys = [defiant reliant offlineAdmin];
  # excelsior added as a third recipient — it runs its own independent
  # AdGuard Home instance (the dns2 pair to reliant's), backed up the same
  # way defiant's and reliant's are.
  "adguardhome/restic-password.age".publicKeys = [defiant reliant excelsior offlineAdmin];
  # Matched to the physical Zigbee coordinator's own NVRAM state, not the
  # host — named for the hardware, not defiant, so it keeps working without
  # a rename if the coordinator moves. reliant reuses this rather than a new
  # secret, which is what lets already-paired devices keep working without
  # a re-pair once the coordinator physically moves to it.
  "zigbee/network-key.age".publicKeys = [defiant reliant offlineAdmin];
  # Shared receiver/station location (lat/lon) — used by adsb today,
  # expected to be reused by a future weather station module too. Not
  # host- or radio-specific, so reliant reuses this rather than a new one.
  "location/coordinates.age".publicKeys = [defiant reliant offlineAdmin];
  # Matched to the physical Z-Wave controller's own NVM state, not the
  # host — same reasoning as zigbee/network-key.age above. reliant reuses
  # this to avoid forcing an unnecessary re-pair of every Z-Wave device
  # once the controller physically moves to it.
  "zwave/secrets.age".publicKeys = [defiant reliant offlineAdmin];
  "thomasga/ssh-id-ed25519-excelsior.age".publicKeys = [excelsior offlineAdmin];
  "thomasga/ssh-id-ed25519-reliant.age".publicKeys = [reliant offlineAdmin];
  "dcs-server/restic-password.age".publicKeys = [excelsior offlineAdmin];
}
