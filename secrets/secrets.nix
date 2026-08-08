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
  "thomasga/restic-password.age".publicKeys = [enterprise-d offlineAdmin];
  "thomasga/nas-smb-credentials.age".publicKeys = [enterprise-d offlineAdmin];
  "thomasga/ssh-id-ed25519-enterprise-d.age".publicKeys = [enterprise-d offlineAdmin];
  "thomasga/github-token.age".publicKeys = [enterprise-d offlineAdmin];
  "thomasga/garmin-username.age".publicKeys = [enterprise-d offlineAdmin];
  "thomasga/garmin-password.age".publicKeys = [enterprise-d offlineAdmin];
  "wifi/agt-home.age".publicKeys = [enterprise-d offlineAdmin];
  "wifi/agt-iot.age".publicKeys = [enterprise-d offlineAdmin];
  "wifi/agt-work.age".publicKeys = [enterprise-d offlineAdmin];
  "thomasga/ssh-id-ed25519-holodeck-01.age".publicKeys = [holodeck-01 offlineAdmin];
  "thomasga/ssh-id-ed25519-defiant.age".publicKeys = [defiant offlineAdmin];
  "defiant/cloudflare-api-token.age".publicKeys = [defiant offlineAdmin];
  "defiant/nas-smb-credentials.age".publicKeys = [defiant offlineAdmin];
  "hass/restic-password.age".publicKeys = [defiant offlineAdmin];
  "zigbee2mqtt/restic-password.age".publicKeys = [defiant offlineAdmin];
  "zwave-js/restic-password.age".publicKeys = [defiant offlineAdmin];
  "adguardhome/restic-password.age".publicKeys = [defiant offlineAdmin];
  "defiant/zigbee-network-key.age".publicKeys = [defiant offlineAdmin];
  # Shared receiver/station location (lat/lon) — used by adsb today,
  # expected to be reused by a future weather station module too.
  "defiant/location.age".publicKeys = [defiant offlineAdmin];
  "defiant/zwave-secrets.age".publicKeys = [defiant offlineAdmin];
  "thomasga/ssh-id-ed25519-excelsior.age".publicKeys = [excelsior offlineAdmin];
  "thomasga/ssh-id-ed25519-reliant.age".publicKeys = [reliant offlineAdmin];
}
