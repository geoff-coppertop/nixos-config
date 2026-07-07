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

    # Devcontainer configs pass --userns=${localEnv:DEVCONTAINER_USERNS:host}
    # so one devcontainer.json works on Docker and rootless Podman alike.
    # Rootless Podman needs keep-id for bind-mounted workspace files to keep
    # the host UID.  Session-level (PAM) rather than shell-level so
    # GUI-launched VS Code sees it, not just interactive shells.
    sessionVariables.DEVCONTAINER_USERNS = "keep-id";
  };

  virtualisation = {
    podman = {
      enable = true;
      # Provide a `docker` shim so tooling that calls docker (e.g. VS Code
      # devcontainer CLI) works without modification.
      dockerCompat = true;
      # Enable DNS resolution between containers on the default network.
      defaultNetwork.settings.dns_enabled = true;
      # Podman 5.0 made pasta the rootless default.  Pasta clones the host's
      # primary outbound interface into the container netns, which fails on
      # dual-homed hosts (here wifi + USB-C ethernet on the same /24): NM only
      # installs the kernel prefix route on one interface, the container sees
      # the other in isolation, and ends up with no reachable gateway.  Ship
      # slirp4netns so the network.default_rootless_network_cmd switch below
      # has a binary to call -- slirp4netns NATs through a private subnet and
      # is host-config-agnostic.
      extraPackages = [pkgs.slirp4netns];
    };

    containers = {
      # localhost must be first so Podman resolves locally-built images (tagged
      # localhost/<name>) before querying external registries.  Without it, the
      # devcontainer updateRemoteUserUID build step triggers Podman's interactive
      # short-name disambiguation prompt: it passes the bare image name (no
      # localhost/ prefix) in its FROM, which doesn't match any local image
      # exactly and falls through to short-name resolution.
      registries.search = ["localhost" "docker.io" "quay.io"];

      containersConf.settings = {
        # Use Docker image format.  The devcontainer CLI's updateRemoteUserUID
        # Dockerfile uses the SHELL instruction, which OCI format does not
        # support and silently ignores with a warning.
        engine.image_default_format = "docker";

        # Pair to extraPackages above: undo podman 5.0's default flip and use
        # slirp4netns instead of pasta for rootless containers.
        network.default_rootless_network_cmd = "slirp4netns";
      };
    };
  };
}
