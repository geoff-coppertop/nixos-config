{
  imports = [../../../users/thomasga/desktop.nix];
  custom.ssh.identitySecret = "ssh-id-ed25519-enterprise-d";
  programs.firefox.configPath = ".mozilla/firefox";

  custom.ai.claude.mcpServers.unifi = {
    enable = true;
    # TODO: set to the real UniFi Network controller address (e.g. its LAN
    # IP or "unifi" if resolvable). Placeholder until confirmed.
    host = "unifi.local";
    credentialsFile = "/run/agenix/thomasga/unifi-network-credentials";
  };
}
