{
  lib,
  config,
  pkgs,
  ...
}: {
  options.custom.ssh.identitySecret = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = "Name of the agenix secret under /run/agenix/thomasga/ holding the SSH private key. When set, the key is copied to ~/.ssh/id_ed25519 and the public key is derived on each rebuild.";
  };

  config = lib.mkIf (config.custom.ssh.identitySecret != null) {
    home.activation.copySshKey = lib.hm.dag.entryAfter ["writeBoundary"] ''
      keyfile="/run/agenix/thomasga/${config.custom.ssh.identitySecret}"
      if [ -f "$keyfile" ]; then
        $DRY_RUN_CMD mkdir -p "$HOME/.ssh"
        $DRY_RUN_CMD chmod 700 "$HOME/.ssh"
        $DRY_RUN_CMD cp -f "$keyfile" "$HOME/.ssh/id_ed25519"
        $DRY_RUN_CMD chmod 600 "$HOME/.ssh/id_ed25519"
        run ${pkgs.openssh}/bin/ssh-keygen -y -f "$keyfile" > "$HOME/.ssh/id_ed25519.pub"
        $DRY_RUN_CMD chmod 644 "$HOME/.ssh/id_ed25519.pub"
      fi
    '';
  };
}
