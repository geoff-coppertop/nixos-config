{
  imports = [./configuration.nix];
  home-manager.users.thomasga = {
    imports = [../../users/thomasga/headless.nix];
    custom.ssh.identitySecret = "ssh-id-ed25519-holodeck-01";
  };
}
