{lib, ...}: let
  sshHosts = import ../../lib/ssh-hosts.nix;

  importedMatchBlocks =
    lib.mapAttrs (_: host: {
      hostname = host.hostName;
      inherit (host) user;
    })
    sshHosts;
in {
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    matchBlocks =
      {
        "*" = {
          addKeysToAgent = "yes";
          hashKnownHosts = false;
        };
      }
      // importedMatchBlocks;
  };
}
