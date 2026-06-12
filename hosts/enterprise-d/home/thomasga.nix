{
  imports = [../../../users/thomasga/desktop.nix];
  custom.ssh.identitySecret = "ssh-id-ed25519-enterprise-d";
  programs.firefox.configPath = ".mozilla/firefox";
}
