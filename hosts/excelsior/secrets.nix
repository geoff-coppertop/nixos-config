_: {
  age.secrets = {
    "thomasga/ssh-id-ed25519-excelsior" = {
      file = ../../secrets/thomasga/ssh-id-ed25519-excelsior.age;
      owner = "thomasga";
    };

    # New, excelsior-only secret — the restic repository password for the
    # dcs-server backup set.
    "dcs-server/restic-password".file = ../../secrets/dcs-server/restic-password.age;

    # All three below are job-keyed, not machine-keyed (docs/secrets.md §
    # Secret Inventory) — each reuses an existing shared entry rather than
    # minting a new one. Every host mounts the same single NAS
    # (lib/nas.nix), so nas-smb-credentials needs no per-host distinction
    # either; the restic repo path already includes the hostname, so
    # sharing these doesn't collide backup data across hosts.
    "thomasga/nas-smb-credentials".file = ../../secrets/thomasga/nas-smb-credentials.age;
    "adguardhome/restic-password".file = ../../secrets/adguardhome/restic-password.age;
    "thomasga/restic-password".file = ../../secrets/thomasga/restic-password.age;

    # Dedicated NAS service account for the media share (not thomasga's personal
    # backup credentials). Create with:
    #   EDITOR=nano nix run .#secret-edit -- secrets/excelsior/nas-smb-credentials.age
    # in username=…/password=… format.
    "excelsior/nas-smb-credentials".file =
      ../../secrets/excelsior/nas-smb-credentials.age;

    # Cloudflare API token for Traefik's ACME DNS-01 wildcard cert.
    "excelsior/cloudflare-api-token" = {
      file = ../../secrets/excelsior/cloudflare-api-token.age;
      owner = "traefik";
    };

    # htpasswd for the Traefik basicAuth middleware protecting the ARM and
    # tinyMediaManager admin UIs (their own auth is weak). Create with:
    #   htpasswd -nB <user>   (paste the line via secret-edit)
    "excelsior/media-admin-htpasswd" = {
      file = ../../secrets/excelsior/media-admin-htpasswd.age;
      owner = "traefik";
    };
  };
}
