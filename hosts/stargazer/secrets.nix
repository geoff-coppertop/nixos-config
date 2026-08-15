{
  # No agenix secrets yet. stargazer's host age key must be enrolled and its
  # per-host secrets created before any are declared here — otherwise these
  # would reference .age files that do not exist (breaking `nix flake check`)
  # or fail to decrypt at activation. Kept as an explicit empty set so the
  # wiring is obvious and ready. See README → Provisioning.
  age.secrets = {};
}
