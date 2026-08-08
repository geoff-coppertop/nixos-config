{
  imports = [./configuration.nix];

  # No home-manager.users entries in this Phase 1 PR: hosts/reliant/home/
  # and the home-manager.users.thomasga import line are user-provisioner's
  # (see CLAUDE.md § Scope) — attaching a user's environment here is Phase 2
  # work, done once this host is confirmed up per
  # docs/provisioning.md § Step 7. flake.nix's homeConfigurations
  # "thomasga@reliant" entry is deferred to that same hand-off: it imports
  # ./home/thomasga.nix directly, which doesn't exist yet, so adding it now
  # would break evaluation of the whole flake.
}
