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
    mapAttrsToList
    mkDefault
    mkEnableOption
    mkIf
    mkMerge
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

  # Emit a bash array literal. The values are only ever expanded at runtime on
  # the host being backed up, never resolved at eval time — see the comment on
  # the resolution loop in `script` below.
  shellArray = name: values: "declare -a ${name}=(${concatMapStringsSep " " escapeShellArg values})";

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

        restic --repo "$repo" backup "''${resolved_paths[@]}" "''${exclude_args[@]}"
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

  brcfg = cfg.backrest;

  # Seed config.json on first launch so each enabled user's restic repo is
  # pre-wired without manual UI setup. repos is empty unless backups are also
  # enabled (enabledUsers is empty otherwise).
  #
  # Schema confirmed against backrest 875c9cb (v1.14.1, matching the pinned
  # nixpkgs package) source, not guessed:
  # - version must be 6 (proto/v1/config.proto's current schema version,
  #   internal/config/migrations/migrations.go's CurrentVersion). A config
  #   with no version field defaults to 0, and internal/config/validate.go
  #   rejects a version-0 config outright once it has any real data (repos
  #   here) rather than treating it as freshly-initialized — confirmed live:
  #   this is exactly what crash-looped backrest.service on excelsior with
  #   "config version 0 is invalid" before this was fixed.
  # - each Repo needs either `guid` (64 chars, matching an existing restic
  #   repo's config) or `autoInitialize = true` — validate.go rejects a repo
  #   with neither. No `password` field is validated; RESTIC_PASSWORD_FILE
  #   via `env` is sufficient on its own.
  seedConfig = pkgs.writeText "backrest-seed.json" (builtins.toJSON {
    version = 6;
    repos =
      mapAttrsToList (userName: userCfg: {
        id = "nas-${userName}";
        uri = repoPath userName;
        env = ["RESTIC_PASSWORD_FILE=${userCfg.passwordFile}"];
        autoInitialize = true;
      })
      enabledUsers;
    plans = [];
    auth.users = [];
  });

  # Replace config.json when it's missing, or when backrest has just failed to
  # start against it several times in a row. Trusts backrest's own verdict on
  # whether the file is loadable rather than this module re-guessing backrest's
  # validation rules externally (an earlier version of this check tried to
  # replicate one specific rule — version <= 0 — and would have missed any
  # other reason backrest might reject a config). Gated on *repeated* failures,
  # not the first one, so a transient NAS/network hiccup on startup can't be
  # mistaken for a broken config and clobber real UI-managed state (plans,
  # schedules) over it. NRestarts is systemd's own consecutive-automatic-
  # restart counter (systemd.exec(5)) — reset on a fresh `systemctl start`, not
  # something this needs to track by hand — so this is keyed on what actually
  # happened, not a guess about what would happen.
  #
  # Confirmed live on excelsior and reliant: a plain existence check alone
  # means a config.json broken by a bad seed (or left behind by an earlier
  # failed deploy) never self-heals just because the generated seed is later
  # fixed — both crash-looped against the same stale file across several
  # redeploys until it was removed by hand.
  backrestInit = pkgs.writeShellScript "backrest-init" ''
    set -eu
    configFile=/var/lib/backrest/config.json

    if [ ! -f "$configFile" ]; then
      install -m 0600 ${seedConfig} "$configFile"
      exit 0
    fi

    restarts=$(${pkgs.systemd}/bin/systemctl show backrest.service -p NRestarts --value)
    if [ "$restarts" -ge 4 ]; then
      echo "backrest.service has failed to start $restarts times in a row; reseeding config.json"
      install -m 0600 ${seedConfig} "$configFile"
    fi
  '';

  # Traefik router + service for a proxied remote backrest instance, keyed by
  # its subdomain so builtins.listToAttrs merges them alongside the local one.
  mkRemoteRouter = r: {
    name = r.subdomain;
    value = {
      rule = "Host(`${r.subdomain}.${config.custom.traefik.acme.domain}`)";
      service = r.subdomain;
      tls = {};
    };
  };

  mkRemoteService = r: {
    name = r.subdomain;
    value.loadBalancer.servers = [{inherit (r) url;}];
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
        };
      }));
    };

    backrest = {
      enable = mkEnableOption "backrest web UI for restic snapshot browsing and restore";

      listenAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Listen address. Set to 0.0.0.0 so the fleet's Traefik host can reach this instance over the LAN.";
      };

      subdomain = mkOption {
        type = types.str;
        description = "Traefik subdomain for this host's backrest (without base domain).";
      };

      proxiedRemotes = mkOption {
        type = types.listOf (types.submodule {
          options = {
            subdomain = mkOption {type = types.str;};
            url = mkOption {type = types.str;};
          };
        });
        default = [];
        description = "Remote backrest instances this host's Traefik reverse-proxies. Only used on the Traefik host.";
      };
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
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
    })

    (mkIf brcfg.enable {
      custom.backups.backrest.subdomain = mkDefault "backup-${config.networking.hostName}";

      systemd.services.backrest = {
        description = "Backrest restic snapshot browser and restore UI";
        wantedBy = ["multi-user.target"];
        after = ["network.target"];

        environment = {
          BACKREST_PORT = "${brcfg.listenAddress}:9898";
          BACKREST_CONFIG = "/var/lib/backrest/config.json";
          BACKREST_DATA = "/var/lib/backrest";
          BACKREST_RESTIC_COMMAND = "${pkgs.restic}/bin/restic";
        };

        serviceConfig = {
          Type = "simple";
          StateDirectory = "backrest";
          Restart = "on-failure";
          RestartSec = "5s";
          ExecStartPre = "${backrestInit}";
          ExecStart = "${pkgs.backrest}/bin/backrest";
        };
      };
    })

    (mkIf (brcfg.enable && config.custom.traefik.enable) {
      services.traefik.dynamicConfigOptions.http = {
        routers =
          {
            backrest = {
              rule = "Host(`${brcfg.subdomain}.${config.custom.traefik.acme.domain}`)";
              service = "backrest";
              tls = {};
            };
          }
          // builtins.listToAttrs (map mkRemoteRouter brcfg.proxiedRemotes);

        services =
          {
            backrest.loadBalancer.servers = [{url = "http://localhost:9898";}];
          }
          // builtins.listToAttrs (map mkRemoteService brcfg.proxiedRemotes);
      };
    })
  ];
}
