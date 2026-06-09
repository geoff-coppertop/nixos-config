{
  imports = [./configuration.nix];
  home-manager.users.thomasga = {
    imports = [../../users/thomasga];
    custom.ssh.identitySecret = "ssh-id-ed25519-enterprise-d";
  };
}
