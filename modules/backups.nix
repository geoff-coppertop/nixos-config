{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit
    (lib)
    concatMapStringsSep
    escapeShellArg
    filterAttrs
    mapAttrs'
    mkEnableOption
    mkIf
    mkOption
    nameValuePair
    optional
    optionalAttrs
    types
    ;

  cfg = config.custom.backups;

  enabledUsers = filterAttrs (_: userCfg: userCfg.enable) cfg.users;

  nasDevice =
    if cfg.nas.protocol == "cifs"
    then "//${cfg.nas.host}/${cfg.nas.share}"
    else "${cfg.nas.host}:${cfg.nas.share}";

  nasFsType =
    if cfg.nas.protocol == "cifs"
    then "cifs"
    else "nfs";

  nasMountOptions =
    [
      "nofail"
      "noauto"
      "x-systemd.automount"
      "x-systemd.idle-timeout=10min"
      "x-systemd.mount-timeout=15s"
    ]
    ++ optional (cfg.nas.protocol == "cifs") "vers=3.0"
    ++ optional (cfg.nas.protocol == "cifs" && cfg.nas.credentialsFile != null)
    "credentials=${cfg.nas.credentialsFile}"
    ++ cfg.nas.mountOptions;

  backupArgs = userCfg:
    concatMapStringsSep " " escapeShellArg userCfg.paths;

  excludeArgs = userCfg:
    concatMapStringsSep " " (pattern: "--exclude=${escapeShellArg pattern}") userCfg.excludePatterns;

  repoPath = userName: "${cfg.nas.mountPoint}/${userName}/${config.networking.hostName}";

  serviceName = userName: "nas-backup-${userName}";

  mkBackupService = userName: userCfg:
    nameValuePair (serviceName userName) {
      description = "Back up ${userName} to the NAS with restic";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];
      wants = ["network-online.target"];

      unitConfig = optionalAttrs config.custom.isLaptop {
        ConditionACPower = true;
      };

      serviceConfig = {
        Type = "oneshot";
        Nice = 19;
        IOSchedulingClass = "best-effort";
        IOSchedulingPriority = 7;
        # The unit runs as root and systemd sets no $HOME for it, so restic's
        # own cache-directory autodetection fails outright ("neither
        # $XDG_CACHE_HOME nor $HOME are defined") before it ever reaches the
        # repository. Let systemd own the directory instead: it creates
        # /var/cache/nas-backup-<name> with the right ownership and mode, and
        # applies its normal cache lifecycle to it. One directory per entry,
        # because each entry is a separate restic repository and they must not
        # share a cache.
        CacheDirectory = serviceName userName;
      };

      environment.RESTIC_CACHE_DIR = "/var/cache/${serviceName userName}";

      path = with pkgs; [coreutils restic util-linux];

      script = ''
        set -eu

        mount ${escapeShellArg cfg.nas.mountPoint} >/dev/null 2>&1 || true

        if ! mountpoint -q ${escapeShellArg cfg.nas.mountPoint}; then
          echo "NAS mount ${cfg.nas.mountPoint} is unavailable; skipping backup"
          exit 0
        fi

        if [ ! -f ${escapeShellArg userCfg.passwordFile} ]; then
          echo "Missing restic password file ${userCfg.passwordFile}; skipping backup"
          exit 0
        fi

        repo=${escapeShellArg (repoPath userName)}
        export RESTIC_PASSWORD_FILE=${escapeShellArg userCfg.passwordFile}

        mkdir -p "$repo"

        # The repository lives on a mounted filesystem, so its `config` file is
        # the authoritative "already initialised" marker. Never probe with
        # `restic snapshots` — that also fails on a stale lock or a transient
        # NAS error, and initialising over a real repository is fatal.
        if [ ! -e "$repo/config" ]; then
          if init_output=$(restic --repo "$repo" init 2>&1); then
            echo "$init_output"
          else
            case "$init_output" in
              *"config file already exists"*)
                echo "restic repository at $repo is already initialised; continuing"
                ;;
              *)
                echo "$init_output" >&2
                exit 1
                ;;
            esac
          fi
        fi

        restic --repo "$repo" backup ${backupArgs userCfg} ${excludeArgs userCfg}
        restic --repo "$repo" forget \
          --keep-daily ${toString cfg.retention.daily} \
          --keep-weekly ${toString cfg.retention.weekly} \
          --keep-monthly ${toString cfg.retention.monthly} \
          --keep-yearly ${toString cfg.retention.yearly} \
          --prune
      '';
    };

  mkBackupTimer = userName: _:
    nameValuePair "${serviceName userName}-timer" {
      description = "Schedule NAS backups for ${userName}";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
        RandomizedDelaySec = "30m";
        Unit = "${serviceName userName}.service";
      };
    };
in {
  options.custom.backups = {
    enable = mkEnableOption "client-pushed NAS backups";

    schedule = mkOption {
      type = types.str;
      default = "daily";
      description = "systemd calendar expression for NAS backup timers.";
    };

    nas = {
      protocol = mkOption {
        type = types.enum ["cifs" "nfs"];
        default = "cifs";
        description = "Transport used to mount the NAS share.";
      };

      host = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Hostname or IP address of the NAS.";
      };

      share = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Share or export name on the NAS.";
      };

      mountPoint = mkOption {
        type = types.str;
        default = "/mnt/nas-backups";
        description = "Local mount point used for the NAS share.";
      };

      credentialsFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Path to an SMB credentials file, typically provided by agenix.";
      };

      mountOptions = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Extra mount options appended to the NAS filesystem mount.";
      };
    };

    retention = {
      daily = mkOption {
        type = types.ints.unsigned;
        default = 7;
        description = "Number of daily restic snapshots to keep.";
      };

      weekly = mkOption {
        type = types.ints.unsigned;
        default = 4;
        description = "Number of weekly restic snapshots to keep.";
      };

      monthly = mkOption {
        type = types.ints.unsigned;
        default = 12;
        description = "Number of monthly restic snapshots to keep.";
      };

      yearly = mkOption {
        type = types.ints.unsigned;
        default = 3;
        description = "Number of yearly restic snapshots to keep.";
      };
    };

    users = mkOption {
      default = {};
      description = "Per-user NAS backup jobs.";
      type = types.attrsOf (types.submodule ({name, ...}: {
        options = {
          enable = mkEnableOption "NAS backups for ${name}";

          paths = mkOption {
            type = types.listOf types.str;
            default = ["/home/${name}"];
            description = "Paths to include in the user's backup set.";
          };

          passwordFile = mkOption {
            type = types.str;
            default = "/run/agenix/${name}/restic-password";
            description = "Path to the restic password file for this user.";
          };

          excludePatterns = mkOption {
            type = types.listOf types.str;
            default = ["/home/${name}/.cache"];
            description = "restic exclude patterns for this user's backup.";
          };
        };
      }));
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.nas.host != null;
        message = "custom.backups.nas.host must be set when NAS backups are enabled.";
      }
      {
        assertion = cfg.nas.share != null;
        message = "custom.backups.nas.share must be set when NAS backups are enabled.";
      }
      {
        assertion = enabledUsers != {};
        message = "Enable at least one entry under custom.backups.users when NAS backups are enabled.";
      }
      {
        assertion = cfg.nas.protocol != "cifs" || cfg.nas.credentialsFile != null;
        message = "custom.backups.nas.credentialsFile must be set for CIFS NAS backups.";
      }
    ];

    environment.systemPackages = [pkgs.restic];

    fileSystems.${cfg.nas.mountPoint} = {
      device = nasDevice;
      fsType = nasFsType;
      options = nasMountOptions;
    };

    systemd.services = mapAttrs' mkBackupService enabledUsers;
    systemd.timers = mapAttrs' mkBackupTimer enabledUsers;
  };
}
