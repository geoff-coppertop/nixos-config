{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkMerge mkOption optionalAttrs types;
  mkTraefikRoute = import ../lib/traefik-route.nix;
  cfg = config.custom.lldap;

  userSubmodule = types.submodule {
    options = {
      id = mkOption {
        type = types.str;
        description = "lldap username -- bootstrap.sh's mandatory 'id' field.";
      };
      email = mkOption {
        type = types.str;
        description = "Mandatory in lldap's own user schema, even for a service account that never reads mail.";
      };
      displayName = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      firstName = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      lastName = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      passwordFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Path to an agenix-managed file containing this user's password,
          passed to bootstrap.sh as the real 'password_file' JSON field
          (confirmed against lldap's own scripts/bootstrap.sh and
          example_configs/bootstrap/bootstrap.md -- password IS settable
          declaratively this way, not just at first-run). Leave null for a
          real household account with no password set here yet -- bootstrap.sh
          only touches the password when this is provided, so the account is
          still created (email/groups/etc. reconciled) but has to get its
          password set by hand through lldap's own UI or "forgot password"
          flow.
        '';
      };
      groups = mkOption {
        type = types.listOf types.str;
        default = [];
        description = ''
          Group names this user belongs to. Both regular groups declared in
          custom.lldap.bootstrap.groups and lldap's own built-in groups
          (lldap_admin, lldap_password_manager, lldap_strict_readonly) work
          here -- bootstrap.sh never treats those three as redundant/deletable
          even when they're not declared in any group config (confirmed
          against the real script: it subtracts exactly those three names from
          its own cleanup candidate list before deciding what to prune).
        '';
      };
    };
  };

  groupSubmodule = types.submodule {
    options.name = mkOption {
      type = types.str;
      description = "Group name -- bootstrap.sh's mandatory (and only) group field.";
    };
  };

  toUserJSON = u:
    pkgs.writeText "lldap-user-${u.id}.json" (builtins.toJSON (
      {inherit (u) id email groups;}
      // optionalAttrs (u.displayName != null) {inherit (u) displayName;}
      // optionalAttrs (u.firstName != null) {inherit (u) firstName;}
      // optionalAttrs (u.lastName != null) {inherit (u) lastName;}
      // optionalAttrs (u.passwordFile != null) {password_file = u.passwordFile;}
    ));

  toGroupJSON = g: pkgs.writeText "lldap-group-${g.name}.json" (builtins.toJSON {inherit (g) name;});

  userConfigsDir = pkgs.linkFarm "lldap-user-configs" (map (u: {
      name = "${u.id}.json";
      path = toUserJSON u;
    })
    cfg.bootstrap.users);

  groupConfigsDir = pkgs.linkFarm "lldap-group-configs" (map (g: {
      name = "${g.name}.json";
      path = toGroupJSON g;
    })
    cfg.bootstrap.groups);

  # bootstrap.sh lives in the same upstream repo as lldap itself
  # (lldap/lldap, scripts/bootstrap.sh) but nixpkgs' services.lldap module
  # only packages the server/frontend/lldap_set_password binary, not this
  # script -- confirmed against the real pkgs.lldap derivation. Pinned to the
  # exact release tag pkgs.lldap.version already builds (not "main", which
  # would silently drift the script out from under whatever lldap version is
  # actually running) -- if nixpkgs ever bumps custom.lldap's version out from
  # under this hash, fetchurl fails loudly at eval/build time rather than
  # silently running a mismatched script; bump the hash then.
  bootstrapScript = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/lldap/lldap/v${pkgs.lldap.version}/scripts/bootstrap.sh";
    hash = "sha256-rVpOhrlsdW+lSaATOm05zTIyduUAxHHO7EUX2DouyLE=";
  };
in {
  options.custom.lldap = {
    enable = mkEnableOption "lldap directory server (LDAP backend for Authelia SSO)";

    subdomain = mkOption {
      type = types.str;
      default = "ad";
      description = "Subdomain for lldap's own admin UI. Never gets the authelia forward-auth middleware -- see docs/homelab-network.md § Self-Lockout Rule.";
    };

    baseDn = mkOption {
      type = types.str;
      example = "dc=coppertop,dc=ca";
      description = "LDAP base DN. Also consumed by custom.authelia to build its bind DN and users/groups search base.";
    };

    adminUsername = mkOption {
      type = types.str;
      default = "admin";
      description = "lldap's own superuser login name (LLDAP_LDAP_USER_DN), distinct from any bootstrap.sh-managed user.";
    };

    adminPasswordFile = mkOption {
      type = types.str;
      description = "Path to an agenix-managed file holding lldap's initial admin password (services.lldap.settings.ldap_user_pass_file).";
    };

    jwtSecretFile = mkOption {
      type = types.str;
      description = "Path to an agenix-managed file holding lldap's JWT secret (services.lldap.settings.jwt_secret_file). Without this lldap falls back to a hardcoded, publicly-known default.";
    };

    httpPort = mkOption {
      type = types.port;
      default = 17170;
      description = "lldap's web UI/GraphQL API port (upstream default).";
    };

    ldapPort = mkOption {
      type = types.port;
      default = 3890;
      description = "lldap's own LDAP protocol port (upstream default). Bound to 127.0.0.1 only -- Authelia is the only consumer, and it runs on this same host.";
    };

    bootstrap = {
      cleanup = mkOption {
        type = types.bool;
        default = true;
        description = ''
          DO_CLEANUP for bootstrap.sh: prune any user/group/membership that
          exists in lldap but isn't declared in custom.lldap.bootstrap.users/
          groups. This is what makes the users/groups lists below the actual
          source of truth rather than a one-time seed. Known non-blocking
          upstream caveat: lldap/lldap#745 reports possible duplicate group
          memberships across repeated bootstrap runs -- not confirmed present
          in this repo's pinned lldap version; watch a few real reruns
          (journalctl -u lldap-bootstrap) before assuming it's fine, rather
          than designing around it preemptively.
        '';
      };

      users = mkOption {
        type = types.listOf userSubmodule;
        default = [];
        description = ''
          Declarative lldap users, reconciled by bootstrap.sh on every
          lldap-bootstrap.service run. Real household accounts are a TODO --
          see hosts/reliant/README.md § lldap -- only Authelia's own LDAP
          bind service account is populated here for real.
        '';
      };

      groups = mkOption {
        type = types.listOf groupSubmodule;
        default = [];
        description = "Declarative lldap groups, reconciled the same way as bootstrap.users above.";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      services.lldap = {
        enable = true;
        settings = {
          http_host = "127.0.0.1";
          http_port = cfg.httpPort;
          ldap_host = "127.0.0.1";
          ldap_port = cfg.ldapPort;
          ldap_base_dn = cfg.baseDn;
          ldap_user_dn = cfg.adminUsername;
          ldap_user_pass_file = cfg.adminPasswordFile;
          # "always": this is a declarative config, not a one-time fix --
          # without it, a UI-side password change (or drift) would silently
          # stick until someone noticed the secret file no longer matched.
          force_ldap_user_pass_reset = "always";
          jwt_secret_file = cfg.jwtSecretFile;
        };
      };

      systemd.services.lldap-bootstrap = {
        description = "Reconcile lldap users/groups from custom.lldap.bootstrap (lldap/lldap's own bootstrap.sh)";
        after = ["lldap.service"];
        requires = ["lldap.service"];
        wantedBy = ["multi-user.target"];
        path = [pkgs.curl pkgs.jq pkgs.jo];
        # Re-run whenever the declared users/groups (or the pinned script
        # itself) change, not just at boot -- systemd restarts a oneshot with
        # RemainAfterExit whose restartTriggers changed on the next
        # nixos-rebuild switch.
        restartTriggers = [userConfigsDir groupConfigsDir bootstrapScript];
        environment = {
          LLDAP_URL = "http://127.0.0.1:${toString cfg.httpPort}";
          LLDAP_ADMIN_USERNAME = cfg.adminUsername;
          LLDAP_ADMIN_PASSWORD_FILE = cfg.adminPasswordFile;
          USER_CONFIGS_DIR = "${userConfigsDir}";
          GROUP_CONFIGS_DIR = "${groupConfigsDir}";
          LLDAP_SET_PASSWORD_PATH = "${pkgs.lldap}/bin/lldap_set_password";
          DO_CLEANUP = lib.boolToString cfg.bootstrap.cleanup;
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.bash}/bin/bash ${bootstrapScript}";
        };
      };
    }

    # Self-register Traefik route for lldap's own admin UI. Deliberately no
    # authelia forward-auth middleware here, ever -- see docs/homelab-network.md
    # § Self-Lockout Rule: Authelia authenticates against lldap, so gating
    # lldap's own login behind Authelia risks a total lockout the moment
    # lldap itself is down, mid-bootstrap, or misconfigured. lldap's own
    # built-in login is the only gate on this route.
    (mkIf config.custom.traefik.enable {
      services.traefik.dynamicConfigOptions.http = mkTraefikRoute {
        name = "lldap";
        inherit (cfg) subdomain;
        port = cfg.httpPort;
        inherit (config.custom.traefik.acme) domain;
      };
    })
  ]);
}
