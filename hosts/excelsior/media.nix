{
  config,
  pkgs,
  ...
}: let
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
  # Verifying custom.autoRip.hardwareEncode actually uses the GPU during a
  # rip (`intel_gpu_top`'s render engine row), not just that it built.
  environment.systemPackages = [pkgs.intel-gpu-tools];

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
  # temporarily unreachable NAS does not block them from starting. podman-arm
  # itself is deliberately not listed: COMPLETED_PATH (and raw/transcode) are
  # all local now, so ARM no longer needs the NAS mount ready to start --
  # only media-sort's own push into movies/tv touches it.
  systemd.services = {
    jellyfin = {
      after = ["mnt-media.mount"];
      wants = ["mnt-media.mount"];
    };
    podman-tinymediamanager = {
      after = ["mnt-media.mount"];
      wants = ["mnt-media.mount"];
    };
    media-sort = {
      after = ["mnt-media.mount"];
      wants = ["mnt-media.mount"];
    };
  };

  custom = {
    # Jellyfin has its own real accounts, so no Traefik middleware. ARM gets
    # authelia@file instead, see docs/homelab-network.md § Authelia
    # Forward-Auth. tinyMediaManager no longer has a web endpoint at all (see
    # custom.mediaManager). openFirewall stays false everywhere; the firewall
    # rules below are the only thing that open these ports, and only to
    # reliant.
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

      settings = {
        # ARM's default HB_ARGS only kept *forced* subtitles, not English
        # ones. --encoder qsv_h265 overrides the preset's own (software)
        # encoder choice with the hardwareEncode QSV build below -- real
        # wall-clock win on this CPU (i5-6500T), but QSV's HEVC encoder is
        # less compression-efficient than software x265, so output will run
        # larger than the presets' own name suggests.
        HB_ARGS_DVD = "--subtitle-lang-list eng --all-subtitles --encoder qsv_h265";
        HB_ARGS_BD = "--subtitle-lang-list eng --all-subtitles --audio-lang-list eng --all-audio --encoder qsv_h265";

        # H.265/HEVC over ARM's H.264 defaults ("HQ 720p30 Surround"/"HQ
        # 1080p30 Surround") -- meaningfully smaller output at comparable
        # visual quality. Confirmed against HandBrake's own official preset
        # list (handbrake.fr/docs, Matroska category) that these two names
        # exist; HandBrake doesn't publish the RF/quality value each bakes
        # in, so the exact size delta isn't known ahead of a real rip.
        HB_PRESET_DVD = "H.265 MKV 720p30";
        HB_PRESET_BD = "H.265 MKV 1080p30";
      };

      # i5-6500T's HD 530 (Skylake, pre-Xe) does hardware HEVC encode.
      # Untested end-to-end -- see modules/auto-rip.nix and
      # pkgs/handbrake-qsv.nix, and confirm a real rip actually uses the GPU
      # (e.g. intel_gpu_top) before trusting this on a production rip.
      hardwareEncode = true;

      # Needed for disc identification; see custom.autoRip.tmdbApiKeyFile.
      tmdbApiKeyFile = config.age.secrets."arm/tmdb-api-key".path;
    };

    # Organize existing rips (and fix ARM's output) into consistent,
    # metadata-rich names Jellyfin scrapes cleanly. Headless now -- triggered
    # by custom.mediaSort, see its onSuccess wiring below -- not a standing
    # web UI.
    mediaManager = {
      enable = true;
      mediaDir = "/mnt/media";
      uid = mediaUid;
      gid = mediaGid;
      movieDataSources = ["/media/movies"];
      tvShowDataSources = ["/media/tv"];
    };

    # ARM can't tell movies from TV apart, so its completed/ output still
    # needs sorting into the movies/tv/ split above before tmm can identify
    # it -- this reuses ARM's own movie/series identification instead of
    # re-guessing it. importDir adds custom.mediaRipping's import-disc as a
    # second, DB-less source into the same pipeline.
    mediaSort = {
      enable = true;
      dbFile = "${config.custom.autoRip.stateDir}/db/arm.db";
      completedDir = "${config.custom.autoRip.stateDir}/completed";
      importDir = config.custom.mediaRipping.importDir;
      mediaDir = "/mnt/media";
      uid = mediaUid;
      gid = mediaGid;
    };

    # Manual fallback for discs ARM misidentifies or fails on, and for
    # legacy DivX/Xvid data discs import-disc copies rather than transcodes.
    mediaRipping = {
      enable = true;
      users = ["thomasga"];
      uid = mediaUid;
      gid = mediaGid;
    };
  };

  # media-sort is the one thing that actually changes movies/tv, so tmm's
  # headless scan only needs to run right after it, not on its own timer.
  systemd.services.media-sort.unitConfig.OnSuccess = ["podman-tinymediamanager.service"];

  networking.firewall.extraCommands = ''
    iptables -I nixos-fw -p tcp -s ${reliantIp} --dport 8096 -j ACCEPT
    iptables -I nixos-fw -p tcp -s ${reliantIp} --dport 8080 -j ACCEPT
  '';
}
