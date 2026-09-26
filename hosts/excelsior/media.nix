{config, ...}: let
  nas = import ../../lib/nas.nix;

  # reliant's reserved LAN IP — the only host allowed to reach the ports
  # below. Matches this file's sibling restriction in configuration.nix for
  # the DCS control page and AdGuard admin UI.
  reliantIp = "192.168.20.15";

  # Shared identity for the media library, so a future ingestion tool (ARM,
  # tinyMediaManager) and Jellyfin can all reach the same CIFS mount without
  # clashing on ownership. Fixed numeric so the mount's uid/gid options are
  # stable.
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

    # Lets Jellyfin read library files written by a future ingestion tool via
    # the shared group.
    users.jellyfin.extraGroups = ["media"];
  };

  # credentials= is the decrypted agenix secret, read by root at mount time.
  # media-svc is a dedicated NAS account scoped to the Media share only,
  # deliberately separate from the backup-svc account this host's
  # custom.backups.nas block uses for the Backups share (lib/nas.nix). Media
  # and Backups are independent top-level shares with independent NAS-side
  # ACLs, so a compromised or misconfigured media pipeline (Jellyfin, ARM,
  # tinyMediaManager) cannot reach backup data, and a backup job cannot
  # rewrite the library.
  fileSystems."/mnt/media" = {
    device = "//${nas.host}/${nas.shares.media}";
    fsType = "cifs";
    options = [
      "nofail"
      "_netdev"
      "vers=3.0"
      "credentials=/run/agenix/media-svc/nas-smb-credentials"
      "uid=${toString mediaUid}"
      "gid=${toString mediaGid}"
      "file_mode=0664"
      "dir_mode=0775"
      "x-systemd.mount-timeout=15s"
    ];
  };

  # Order the services after the mount, but softly (wants, not requires) so a
  # temporarily unreachable NAS does not block them from starting.
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
    # Jellyfin has its own real accounts, so no Traefik middleware. ARM and
    # tinyMediaManager get authelia@file instead, see docs/homelab-network.md
    # § Authelia Forward-Auth. openFirewall stays false everywhere; the
    # firewall rules below are the only thing that open these ports, and only
    # to reliant.
    jellyfin = {
      enable = true;
      openFirewall = false;
    };

    autoRip = {
      enable = true;
      openFirewall = false;
      bindAddress = "0.0.0.0";
      mediaDir = "/mnt/media";
      uid = mediaUid;
      gid = mediaGid;

      # rip.coppertop.ca is behind authelia@file -- ARM's own login would
      # just be a second prompt on top of SSO.
      disableLogin = true;

      # /dev/sg1: this drive's SCSI generic node, needed for Blu-ray. Not
      # sg0 -- that's an unrelated SATA device. Re-check via `readlink -f
      # /sys/class/scsi_generic/sg*/device` vs `.../block/sr0/device` if
      # this ever changes.
      extraDevices = ["/dev/sg1"];

      # ARM mounts the disc itself, which needs CAP_SYS_ADMIN regardless of
      # user -- dropped by default without --privileged (which this module
      # deliberately avoids).
      extraOptions = ["--cap-add=SYS_ADMIN"];

      # ARM's default HB_ARGS only kept *forced* subtitles, not English ones.
      settings = {
        HB_ARGS_DVD = "--subtitle-lang-list eng --all-subtitles";
        HB_ARGS_BD = "--subtitle-lang-list eng --all-subtitles --audio-lang-list eng --all-audio";
      };

      # Needed for disc identification; see custom.autoRip.tmdbApiKeyFile.
      tmdbApiKeyFile = config.age.secrets."arm/tmdb-api-key".path;
    };

    # Organize existing rips (and fix ARM's output) into consistent,
    # metadata-rich names Jellyfin scrapes cleanly. Reached at
    # library.coppertop.ca.
    mediaManager = {
      enable = true;
      openFirewall = false;
      bindAddress = "0.0.0.0";
      mediaDir = "/mnt/media";
      uid = mediaUid;
      gid = mediaGid;
      movieDataSources = ["/media/movies"];
      tvShowDataSources = ["/media/tv"];
    };

    # ARM can't tell movies from TV apart, so its incoming/ output still
    # needs sorting into the movies/tv/ split above before tmm can identify
    # it -- this reuses ARM's own movie/series identification instead of
    # re-guessing it.
    mediaSort = {
      enable = true;
      dbFile = "${config.custom.autoRip.stateDir}/db/arm.db";
      mediaDir = "/mnt/media";
      uid = mediaUid;
      gid = mediaGid;
    };
  };

  networking.firewall.extraCommands = ''
    iptables -I nixos-fw -p tcp -s ${reliantIp} --dport 8096 -j ACCEPT
    iptables -I nixos-fw -p tcp -s ${reliantIp} --dport 8080 -j ACCEPT
    iptables -I nixos-fw -p tcp -s ${reliantIp} --dport 4000 -j ACCEPT
  '';
}
