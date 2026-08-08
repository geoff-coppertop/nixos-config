_: {
  age.secrets = {
    "thomasga/nas-smb-credentials" = {
      file = ../../secrets/thomasga/nas-smb-credentials.age;
      owner = "thomasga";
    };
    "thomasga/restic-password".file =
      ../../secrets/thomasga/restic-password.age;
    "thomasga/ssh-id-ed25519-reliant" = {
      file = ../../secrets/thomasga/ssh-id-ed25519-reliant.age;
      owner = "thomasga";
    };

    # Host-scoped, not job-keyed, matching defiant/cloudflare-api-token —
    # Cloudflare DNS-01 tokens in this repo are per-host, not shared. Not
    # yet created: secrets/reliant/cloudflare-api-token.age does not exist
    # and secrets/secrets.nix has no recipient entry for it yet. Both are
    # secrets-warden's hand-off (see docs/secrets.md § Creating Or Rotating
    # a Secret); this activation will fail until that lands.
    "reliant/cloudflare-api-token" = {
      file = ../../secrets/reliant/cloudflare-api-token.age;
      owner = "traefik";
    };
  };
}
