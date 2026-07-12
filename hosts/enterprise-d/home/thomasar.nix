{
  imports = [../../../users/thomasar/desktop.nix];
  # No custom.ssh.identitySecret: the test account has no outbound SSH key, so
  # it needs no agenix secret (the option defaults to null).
}
