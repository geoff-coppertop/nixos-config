{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkMerge mkOption types;
  mkTraefikRoute = import ../lib/traefik-route.nix;
  cfg = config.custom.lldap;

  accountSubmodule = types.submodule {
    freeformType = (pkgs.formats.json {}).type;
    options = {
      id = mkOption {
        type = types.str;
        description = "lldap username (login id).";
      };
      email = mkOption {
        type = types.str;
        description = "Account email address.";
      };
      password_file = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Path to a file containing this account's password (agenix-managed).
          Reconciled declaratively by bootstrap.sh on every rebuild via
          lldap_set_password. Omit for household users who should set their
          own password through lldap's own UI on first login; required for
          service accounts (e.g. Authelia's LDAP bind user) so both sides of
          that bind agree without a manual step.
        '';
      };
      groups = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Group names (custom.lldap.groups keys) this account belongs to.";
      };
    };
  };

  groupSubmodule = types.submodule {
    freeformType = (pkgs.formats.json {}).type;
    options = {
      name = mkOption {
        type = types.str;
        description = "Group name.";
      };
    };
  };

  # bootstrap.sh (see below) reads one JSON file per account/group from a
  # directory, keyed only by content (id/name), not filename — the filename
  # itself is arbitrary, so the Nix attrset key is reused for readability.
  # Nulls are stripped before rendering: bootstrap.md documents that an
  # omitted non-mandatory field gets cleared in lldap, which is the desired
  # declarative behavior, but a literal JSON `null` isn't the same as an
  # absent key and risks the script mishandling it.
  toBootstrapJson = attrs: builtins.toJSON (lib.filterAttrsRecursive (_: v: v != null) attrs);

  userConfigFiles =
    lib.mapAttrsToList
    (username: user: pkgs.writeText "${username}.json" (toBootstrapJson user))
    cfg.users;

  groupConfigFiles =
    lib.mapAttrsToList
    (groupName: group: pkgs.writeText "${groupName}.json" (toBootstrapJson group))
    cfg.groups;

  # bootstrap.sh isn't packaged by nixpkgs' lldap derivation (it's an
  # example/ops script, not part of the built binary) — pulled directly from
  # the same source tree nixpkgs already fetches for the pinned lldap
  # version, so it stays in lockstep with whatever lldap version this host
  # actually runs rather than drifting against a separately-pinned copy.
  # Confirmed against the real upstream source at v0.6.3 (matching the
  # nixpkgs revision this was written against): the script lives at
  # scripts/bootstrap.sh (the bootstrap.md doc link to it is relative and
  # slightly misleading), reads USER_CONFIGS_DIR/GROUP_CONFIGS_DIR, and
  # supports LLDAP_ADMIN_PASSWORD_FILE / DO_CLEANUP as env vars. Re-verify
  # this path if the pinned lldap version changes.
  bootstrapScript = "${pkgs.lldap.src}/scripts/bootstrap.sh";
in {
  options.custom.lldap = {
    enable = mkEnableOption "lldap directory service (LDAP backend for Authelia)";

    httpPort = mkOption {
      type = types.port;
      default = 17170;
      description = "Port for lldap's web admin UI.";
    };

    ldapPort = mkOption {
      type = types.port;
      default = 3890;
      description = "Port for the LDAP protocol listener.";
    };

    baseDn = mkOption {
      type = types.str;
      example = "dc=coppertop,dc=ca";
      description = "Base DN for the LDAP directory.";
    };

    adminSubdomain = mkOption {
      type = types.str;
      default = "ad";
      description = "Subdomain for lldap's web admin UI when custom.traefik.enable is set on this host.";
    };

    jwtSecretFile = mkOption {
      type = types.str;
      description = "Path to a file containing lldap's JWT secret (agenix-managed).";
    };

    initialAdminPasswordFile = mkOption {
      type = types.str;
      description = ''
        Path to a file containing lldap's admin password (agenix-managed).
        Also used as LLDAP_ADMIN_PASSWORD_FILE by the bootstrap reconciliation
        service to authenticate against lldap's GraphQL API.
      '';
    };

    users = mkOption {
      type = types.attrsOf accountSubmodule;
      default = {};
      description = ''
        Declarative lldap accounts, reconciled against the live server by
        bootstrap.sh on every rebuild (git-ops style: this attrset is the
        source of truth, drift introduced through lldap's own UI gets
        pruned back on the next switch). Attribute name is used only for
        the generated config filename; `id` is the actual lldap username.
      '';
    };

    groups = mkOption {
      type = types.attrsOf groupSubmodule;
      default = {};
      description = "Declarative lldap groups, reconciled the same way as users.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      # Not DynamicUser (the module default): lldap's settings.*_file options
      # are read directly by the lldap process after it drops privileges, not
      # loaded by systemd-as-root the way Authelia's LoadCredential-backed
      # secrets are (see modules/authelia.nix). A DynamicUser's UID is only
      # allocated at start, so an agenix secret can't be chowned to it ahead
      # of time — a static user makes the secret ownership deterministic,
      # matching the rest of this repo's agenix `owner = "<service>"` pattern
      # (e.g. traefik/cloudflare-api-token, zwave/secrets).
      users.groups.lldap = {};
      users.users.lldap = {
        isSystemUser = true;
        group = "lldap";
      };

      services.lldap = {
        enable = true;
        settings = {
          ldap_port = cfg.ldapPort;
          http_port = cfg.httpPort;
          ldap_base_dn = cfg.baseDn;
          ldap_user_pass_file = cfg.initialAdminPasswordFile;
          # "always" (not `true`): this is a declarative workflow, not a
          # one-time fix — the admin password should always track this
          # agenix secret, not drift once someone changes it via the UI.
          force_ldap_user_pass_reset = "always";
          jwt_secret_file = cfg.jwtSecretFile;
        };
      };

      systemd.services.lldap.serviceConfig = {
        DynamicUser = lib.mkForce false;
        User = "lldap";
        Group = "lldap";
      };

      environment.etc =
        lib.listToAttrs (map (f: {
            name = "lldap-bootstrap/user-configs/${f.name}";
            value = {source = f;};
          })
          userConfigFiles)
        // lib.listToAttrs (map (f: {
            name = "lldap-bootstrap/group-configs/${f.name}";
            value = {source = f;};
          })
          groupConfigFiles);

      systemd.services.lldap-bootstrap = {
        description = "Reconcile lldap users/groups from declarative JSON (lldap bootstrap.sh)";
        after = ["lldap.service"];
        wants = ["lldap.service"];
        path = [pkgs.curl pkgs.jq pkgs.jo];
        environment = {
          LLDAP_URL = "http://127.0.0.1:${toString cfg.httpPort}";
          LLDAP_ADMIN_USERNAME = "admin";
          LLDAP_ADMIN_PASSWORD_FILE = cfg.initialAdminPasswordFile;
          USER_CONFIGS_DIR = "/etc/lldap-bootstrap/user-configs";
          GROUP_CONFIGS_DIR = "/etc/lldap-bootstrap/group-configs";
          LLDAP_SET_PASSWORD_PATH = "${pkgs.lldap}/bin/lldap_set_password";
          # Prune anything created out-of-band (through lldap's own UI)
          # that isn't declared in custom.lldap.users/groups, so this
          # attrset stays the actual source of truth rather than a
          # one-time seed. Known caveat: lldap/lldap#745 reports repeated
          # bootstrap.sh runs via the GraphQL API can duplicate group
          # memberships on some versions — not reproduced yet against the
          # version this module pins; verify group membership after the
          # first few real reruns before trusting this in the steady state.
          DO_CLEANUP = "true";
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.bash}/bin/bash ${bootstrapScript}";
        };
      };

      # bootstrap.sh needs to rerun on every switch, not just when the
      # generated JSON's content changes — DO_CLEANUP's whole point is
      # pruning drift introduced through lldap's own UI between rebuilds,
      # which a content-hash-based restartTrigger would miss. Services are
      # already restarted by the time activation scripts run, so this fires
      # after lldap itself is up; --no-block keeps activation from hanging
      # on lldap's own startup or a slow GraphQL round-trip.
      system.activationScripts.lldapBootstrapTrigger = lib.stringAfter ["users" "etc"] ''
        ${pkgs.systemd}/bin/systemctl start --no-block lldap-bootstrap.service || true
      '';
    }

    (mkIf config.custom.traefik.enable {
      services.traefik.dynamicConfigOptions.http = mkTraefikRoute {
        name = "lldap";
        subdomain = cfg.adminSubdomain;
        port = cfg.httpPort;
        inherit (config.custom.traefik.acme) domain;
        # Deliberately NOT behind the authelia middleware (modules/authelia.nix):
        # Authelia authenticates against lldap, so gating this route on Authelia
        # would self-lock if lldap is ever down, misconfigured, or mid-bootstrap
        # before any accounts exist — the same class of problem as Authelia
        # protecting its own portal route. lldap's own username/password login,
        # plus network-level scoping (LAN-only via unbound's access-control;
        # LAN+WireGuard subnet once that exists; never WAN-exposed), is the
        # actual protection for this route.
      };
    })
  ]);
}
