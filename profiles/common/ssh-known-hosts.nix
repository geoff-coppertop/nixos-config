{lib, ...}: let
  sshHosts = import ../../lib/ssh-hosts.nix;

  knownHosts = lib.mapAttrs' (
    name: host:
      lib.nameValuePair name {
        hostNames = [host.hostName] ++ host.aliases;
        inherit (host) publicKey;
      }
  ) (lib.filterAttrs (_: host: host.publicKey != null) sshHosts);
in {
  programs.ssh.knownHosts = knownHosts;
}
