{
  imports = [
    ../../../users/thomasga/desktop.nix
    ../../../users/common/syncthing.nix
  ];
  custom = {
    ssh.identitySecret = "ssh-id-ed25519-enterprise-d";
    syncthing.enable = true;
  };
  programs.firefox.configPath = ".mozilla/firefox";
}
