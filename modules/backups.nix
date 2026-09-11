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
    flatten
    mapAttrs'
    mapAttrsToList
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    nameValuePair
    optional
    optionalAttrs
    toLower
    types
    ;

  cfg = config.custom.backups;

  enabledUsers = filterAttrs (_: userCfg: userCfg.enable) cfg.users;

  # Entries that carry their own `nas` override, and therefore get their own
  # mount rather than sharing the host-wide one.
  overridingUsers = filterAttrs (_: userCfg: userCfg.nas != null) enabledUsers;

  # The NAS coordinates that apply to one entry: its own override when it has
  # one, otherwise the host-wide block.
  nasFor = userCfg:
    if userCfg.nas != null
    then userCfg.nas
    else cfg.nas;

  # The local mount point for one NAS target. Named after the *share*, not
  # after which module slot (host-wide vs. per-entry override) or which job
  # uses it — a host's mix of jobs against a share can change over time, but
  # what a given share is called does not, so this is the one naming scheme
  # that stays accurate no matter how the entries using it change. Explicit
  # `mountPoint` always wins when set.
  effectiveMountPoint = nas:
    if nas.mountPoint != null
    then nas.mountPoint
    else "/mnt/nas-${toLower nas.share}";

  # The option set describing one NAS target. Used verbatim for the host-wide
  # `custom.backups.nas` block and for each entry's optional override, so the
  # two always have the same shape.
  mkNasOptions = {
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
      type = types.nullOr types.str;
      default = null;
      description = ''
        Local mount point used for the NAS share. Defaults to
        `/mnt/nas-<share, lowercased>` when unset, so the mount point always
        names the share it actually holds regardless of which entries use it;
        override only if that derived name collides or you want something
        else.
      '';
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

  nasDevice = nas:
    if nas.protocol == "cifs"
    then "//${nas.host}/${nas.share}"
    else "${nas.host}:${nas.share}";

  nasFsType = nas:
    if nas.protocol == "cifs"
    then "cifs"
    else "nfs";

  nasMountOptions = nas:
    [
      "nofail"
      "noauto"
      "x-systemd.automount"
      "x-systemd.idle-timeout=10min"
      "x-systemd.mount-timeout=15s"
    ]
    ++ optional (nas.protocol == "cifs") "vers=3.0"
    ++ optional (nas.protocol == "cifs" && nas.credentialsFile != null)
    "credentials=${nas.credentialsFile}"
    ++ nas.mountOptions;

  mkNasFileSystem = nas: {
    device = nasDevice nas;
    fsType = nasFsType nas;
    options = nasMountOptions nas;
  };

  # Assertions that must hold for any NAS target, host-wide or per-entry. The
  # per-entry copies exist so a half-filled override fails evaluation with a
  # pointed message instead of quietly producing `///` as a device path.
  nasAssertions = optionPath: nas: [
    {
      assertion = nas.host != null;
      message = "${optionPath}.host must be set when NAS backups are enabled.";
    }
    {
      assertion = nas.share != null;
      message = "${optionPath}.share must be set when NAS backups are enabled.";
    }
    {
      assertion = nas.protocol != "cifs" || nas.credentialsFile != null;
      message = "${optionPath}.credentialsFile must be set for CIFS NAS backups.";
    }
  ];

  mkOverrideAssertions = userName: userCfg:
    nasAssertions "custom.backups.users.${userName}.nas" userCfg.nas;

  overrideAssertions = flatten (mapAttrsToList mkOverrideAssertions overridingUsers);

  mkOverrideFileSystem = _: userCfg: {${effectiveMountPoint userCfg.nas} = mkNasFileSystem userCfg.nas;};

  # One extra mount per entry that overrides the host-wide NAS target.
  overrideFileSystems = mapAttrsToList mkOverrideFileSystem overridingUsers;

  # Emit a bash array literal. The values are only ever expanded at runtime on
  # the host being backed up, never resolved at eval time — see the comment on
  # the resolution loop in `script` below.
  shellArray = name: values: "declare -a ${name}=(${concatMapStringsSep " " escapeShellArg values})";

  repoPath = userName: userCfg: "${effectiveMountPoint (nasFor userCfg)}/${userName}/${config.networking.hostName}";

  serviceName = userName: "nas-backup-${userName}";

  mkBackupService = userName: userCfg: let
    mountPoint = effectiveMountPoint (nasFor userCfg);
  in
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

        mount ${escapeShellArg mountPoint} >/dev/null 2>&1 || true

        if ! mountpoint -q ${escapeShellArg mountPoint}; then
          echo "NAS mount ${mountPoint} is unavailable; skipping backup"
          exit 0
        fi

        if [ ! -f ${escapeShellArg userCfg.passwordFile} ]; then
          echo "Missing restic password file ${userCfg.passwordFile}; skipping backup"
          exit 0
        fi

        repo=${escapeShellArg (repoPath userName userCfg)}
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

        # A systemd `StateDirectory=`/`CacheDirectory=` belonging to a
        # DynamicUser service is not a directory: systemd creates
        # /var/lib/private/<name> and leaves /var/lib/<name> as a symlink to
        # it. restic does not dereference a symlink handed to it as a
        # top-level backup path — it records the symlink node and never walks
        # the target — so such an entry produced 0 B snapshots containing only
        # the bare path components. Canonicalise every configured path here,
        # at runtime on the host being backed up: the path does not exist on
        # whatever machine evaluates this configuration, so this cannot be
        # done at eval time. `readlink -f` is a no-op for an ordinary
        # directory, so non-symlink entries are unaffected.
        ${shellArray "configured_paths" userCfg.paths}
        declare -a resolved_paths=()

        for configured in "''${configured_paths[@]}"; do
          if ! resolved=$(readlink -f -- "$configured"); then
            resolved=$configured
          fi
          if [ "$resolved" != "$configured" ]; then
            echo "Backup path $configured resolves to $resolved; backing up the resolved path"
          fi
          resolved_paths+=("$resolved")
        done

        # Exclude patterns are written against the *configured* path, but
        # restic matches an absolute pattern against the path as it appears in
        # the snapshot — which is now the resolved one. Keep the configured
        # form (it is still correct for every non-symlink path, and for a
        # pattern already written against the resolved path) and additionally
        # emit a prefix-rewritten form for each path that resolved elsewhere.
        ${shellArray "exclude_patterns" userCfg.excludePatterns}
        declare -a exclude_args=()

        for pattern in "''${exclude_patterns[@]}"; do
          exclude_args+=("--exclude=$pattern")
          index=0
          while [ "$index" -lt "''${#configured_paths[@]}" ]; do
            configured=''${configured_paths[$index]}
            resolved=''${resolved_paths[$index]}
            if [ "$resolved" != "$configured" ]; then
              case "$pattern" in
                "$configured"/*)
                  exclude_args+=("--exclude=$resolved''${pattern#"$configured"}")
                  ;;
              esac
            fi
            index=$((index + 1))
          done
        done

        # --retry-lock: the units are `wantedBy = multi-user.target`, so a
        # `nixos-rebuild switch` starts a backup even while the timer-driven
        # one is still running. Without it the second invocation fails
        # immediately on the first run's lock; with it, it waits and then
        # proceeds. This does NOT recover a lock left behind by a process that
        # is already gone — restic decides staleness from the recorded
        # host+PID being dead, and a PID recycled across a reboot looks alive
        # to that check, so such a lock has to be cleared by hand. See
        # docs/backups.md § Known Gotchas.
        restic --repo "$repo" backup --retry-lock 5m "''${resolved_paths[@]}" "''${exclude_args[@]}"
        restic --repo "$repo" forget \
          --retry-lock 5m \
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

    nas = mkNasOptions;

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
            description = ''
              Paths to include in the user's backup set. Each is canonicalised
              with `readlink -f` at runtime before being handed to restic, so a
              systemd DynamicUser state directory such as `/var/lib/AdGuardHome`
              (a symlink to `private/AdGuardHome`) is backed up by content
              rather than as a bare symlink node.
            '';
          };

          passwordFile = mkOption {
            type = types.str;
            default = "/run/agenix/${name}/restic-password";
            description = "Path to the restic password file for this user.";
          };

          excludePatterns = mkOption {
            type = types.listOf types.str;
            default = ["/home/${name}/.cache"];
            description = ''
              restic exclude patterns for this user's backup. Write them against
              the configured `paths`; when a path canonicalises to a different
              location, matching patterns are additionally re-emitted against the
              resolved prefix.
            '';
          };

          nas = mkOption {
            type = types.nullOr (types.submodule {
              options = mkNasOptions;
            });
            default = null;
            description = ''
              Optional per-entry NAS target, same shape as the host-wide
              `custom.backups.nas` block. Leave it `null` (the default) and the
              entry uses the host-wide mount. Set it when this one job needs a
              different NAS account, share or host than the rest of the
              machine — for example a personal home-directory backup going to
              the person's own share while the appliance jobs on the same host
              use a shared service account. An entry with an override gets its
              own mount — named `/mnt/nas-<share, lowercased>` by default, same
              derivation as the host-wide block — and its own restic
              repository underneath it.
            '';
          };
        };
      }));
    };
  };

  config = mkIf cfg.enable {
    assertions =
      nasAssertions "custom.backups.nas" cfg.nas
      ++ [
        {
          assertion = enabledUsers != {};
          message = "Enable at least one entry under custom.backups.users when NAS backups are enabled.";
        }
      ]
      ++ overrideAssertions;

    environment.systemPackages = [pkgs.restic];

    # The host-wide mount, plus one extra mount per entry that overrides it.
    # mkMerge rather than `//` so an override that collides with the host-wide
    # mount point, or with another override's, is a loud conflict instead of a
    # silently dropped definition.
    fileSystems = mkMerge ([{${effectiveMountPoint cfg.nas} = mkNasFileSystem cfg.nas;}] ++ overrideFileSystems);

    systemd.services = mapAttrs' mkBackupService enabledUsers;
    systemd.timers = mapAttrs' mkBackupTimer enabledUsers;
  };
}
