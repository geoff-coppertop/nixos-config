{...}: let
  nas = import ../../lib/nas.nix;

  # Shared identity for the media library so ARM (which writes ripped files) and
  # Jellyfin (which reads them) both reach the same CIFS mount. Fixed numeric so
  # the mount's uid/gid options are stable.
  mediaUid = 5000;
  mediaGid = 5000;
in {
  users = {
    groups.media.gid = mediaGid;

    users.media = {
      isSystemUser = true;
      uid = mediaUid;
      group = "media";
      description = "Owns the Jellyfin media library mount";
    };

    # Let Jellyfin read library files written by ARM via the shared group.
    users.jellyfin.extraGroups = ["media"];
  };

  # ARM writes as media:media (mount owner); Jellyfin reads via the media group
  # (file_mode grants group read, dir_mode group traverse). credentials= is the
  # decrypted agenix secret, read by root at mount time.
  fileSystems."/mnt/media" = {
    device = "//${nas.host}/${nas.shares.media}";
    fsType = "cifs";
    options = [
      "nofail"
      "_netdev"
      "vers=3.0"
      "credentials=/run/agenix/excelsior/nas-smb-credentials"
      "uid=${toString mediaUid}"
      "gid=${toString mediaGid}"
      "file_mode=0664"
      "dir_mode=0775"
      "x-systemd.mount-timeout=15s"
    ];
  };

  # Order the services after the mount, but softly (wants, not requires) so a
  # temporarily unreachable NAS does not block Jellyfin or ARM from starting.
  systemd.services = {
    jellyfin = {
      after = ["mnt-media.mount"];
      wants = ["mnt-media.mount"];
    };
    podman-arm = {
      after = ["mnt-media.mount"];
      wants = ["mnt-media.mount"];
    };
    podman-tinymediamanager = {
      after = ["mnt-media.mount"];
      wants = ["mnt-media.mount"];
    };
  };

  custom = {
    # Firewalls closed: this host's Traefik fronts all three on loopback.
    jellyfin = {
      enable = true;
      openFirewall = false;
    };

    autoRip = {
      enable = true;
      openFirewall = false;
      mediaDir = "/mnt/media";
      uid = mediaUid;
      gid = mediaGid;
    };

    # Organize existing rips (and fix ARM's output) into consistent,
    # metadata-rich names Jellyfin scrapes cleanly. Reached at tmm.coppertop.ca
    # behind Traefik basicAuth.
    mediaManager = {
      enable = true;
      mediaDir = "/mnt/media";
      uid = mediaUid;
      gid = mediaGid;
    };
  };

  # The jellyfin/autoRip/mediaManager modules self-register their routers on
  # this host's Traefik. ARM and tinyMediaManager have weak built-in auth, so
  # attach a shared basicAuth middleware to their routers; Jellyfin (its own
  # accounts) is left open. htpasswd is an agenix secret read by Traefik.
  services.traefik.dynamicConfigOptions.http = {
    routers.arm.middlewares = ["media-admin"];
    routers.tmm.middlewares = ["media-admin"];
    middlewares.media-admin.basicAuth.usersFile = "/run/agenix/excelsior/media-admin-htpasswd";
  };
}
