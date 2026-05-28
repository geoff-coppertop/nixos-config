{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    gh
    podman-compose
  ];

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };
}
