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

  # Activation script to securely place the key in the standard Linux location (~/.ssh/id_ed25519)
  # without breaking Nix pure evaluation mode.
  home.activation.copySshKey = lib.hm.dag.entryAfter ["writeBoundary"] ''
    # Ensure the .ssh directory exists
    $DRY_RUN_CMD mkdir -p $HOME/.ssh
    $DRY_RUN_CMD chmod 700 $HOME/.ssh

    # Copy the key from agenix to the standard Linux location if the source exists
    if [ -f "/run/agenix/thomasga/ssh-id-ed25519" ]; then
      $DRY_RUN_CMD cp -f "/run/agenix/thomasga/ssh-id-ed25519" "$HOME/.ssh/id_ed25519"
      $DRY_RUN_CMD chmod 600 "$HOME/.ssh/id_ed25519"
    fi
  '';
}
