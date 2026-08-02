{
  imports = [
    ../../../users/thomasga/desktop.nix
    # Desktop-only "cough button": mutes Discord's mic while a HOTAS button is
    # held (so the squadron does not hear DCS/VAICOM voice commands). The HOTAS
    # lives on this machine, so it is imported here rather than in the shared
    # desktop.nix.
    ../../../users/thomasga/discord-cough-mute.nix
  ];

  # String only — the copy is gated on the file existing at
  # /run/agenix/thomasga/ssh-id-ed25519-stargazer, which appears once the
  # secret is provisioned (README). No eval-time dependency on the .age file.
  custom.ssh.identityKeyName = "ssh-id-ed25519-stargazer";
  programs.firefox.configPath = ".mozilla/firefox";
}
