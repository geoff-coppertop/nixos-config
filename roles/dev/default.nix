{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    gh
    docker-compose
  ];

  virtualisation.docker.enable = true;
}
