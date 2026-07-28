{lib, ...}: let
  sshHosts = import ../../lib/ssh-hosts.nix;

  importedSettings =
    lib.mapAttrs (_: host: {
      HostName = host.hostName;
      User = host.user;
    })
    sshHosts;
in {
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    settings =
      {
        "*" = {
          AddKeysToAgent = "yes";
          HashKnownHosts = false;
        };
      }
      // importedSettings;
  };
}
