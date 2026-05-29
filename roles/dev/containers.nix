{pkgs, ...}: {
  environment = {
    systemPackages = with pkgs; [
      podman-compose
    ];

    # Disable short-name aliasing so Podman never prompts; it tries each
    # registry in order and uses the first match.
    etc."containers/registries.conf.d/short-name-mode.conf".text = ''
      short-name-mode = "disabled"
    '';
  };

  virtualisation = {
    podman = {
      enable = true;
      # Provide a `docker` shim so tooling that calls docker (e.g. VS Code
      # devcontainer CLI) works without modification.
      dockerCompat = true;
      # Enable DNS resolution between containers on the default network.
      defaultNetwork.settings.dns_enabled = true;
    };

    containers = {
      # localhost must be first so Podman resolves locally-built images (tagged
      # localhost/<name>) before querying external registries.  Without it, the
      # devcontainer updateRemoteUserUID build step triggers Podman's interactive
      # short-name disambiguation prompt: it passes the bare image name (no
      # localhost/ prefix) in its FROM, which doesn't match any local image
      # exactly and falls through to short-name resolution.
      registries.search = ["localhost" "docker.io" "quay.io"];

      # Use Docker image format.  The devcontainer CLI's updateRemoteUserUID
      # Dockerfile uses the SHELL instruction, which OCI format does not support
      # and silently ignores with a warning.
      containersConf.settings.engine.image_default_format = "docker";
    };
  };
}
