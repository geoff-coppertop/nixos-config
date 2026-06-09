{
  imports = [./configuration.nix];
  home-manager.users.thomasga = {lib, ...}: {
    imports = [../../users/thomasga];
    home.activation.copySshKey = lib.hm.dag.entryAfter ["writeBoundary"] ''
      keyfile="/run/agenix/thomasga/ssh-id-ed25519-enterprise-d"
      if [ -f "$keyfile" ]; then
        $DRY_RUN_CMD mkdir -p "$HOME/.ssh"
        $DRY_RUN_CMD chmod 700 "$HOME/.ssh"
        $DRY_RUN_CMD cp -f "$keyfile" "$HOME/.ssh/id_ed25519"
        $DRY_RUN_CMD chmod 600 "$HOME/.ssh/id_ed25519"
        run ssh-keygen -y -f "$keyfile" > "$HOME/.ssh/id_ed25519.pub"
        $DRY_RUN_CMD chmod 644 "$HOME/.ssh/id_ed25519.pub"
      fi
    '';
  };
}
