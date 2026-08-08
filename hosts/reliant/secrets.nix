_: {
  age.secrets = {
    # thomasga/ssh-id-ed25519-reliant: added automatically by
    # `nix develop -c python3 tools/enroll.py reliant` (docs/provisioning.md
    # § Step 2, secrets-warden's hand-off) — the age identity and this
    # machine's SSH login key don't exist yet. enroll.py only writes this
    # file itself when it doesn't already exist, so because this Phase 1 PR
    # pre-creates it, secrets-warden needs to add that entry here by hand
    # after running enroll.py (or delete this file first and let enroll.py
    # generate it fresh).
    #
    # Add further machine-specific secrets here (NAS, restic, service
    # secrets) as Phase 2 work enables them.
  };
}
