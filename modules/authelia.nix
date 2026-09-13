{
  config,
  lib,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkMerge mkOption types;
  mkTraefikRoute = import ../lib/traefik-route.nix;
  cfg = config.custom.authelia;
  inherit (config.custom.traefik.acme) domain;
  authUrl = "https://${cfg.subdomain}.${domain}/";
in {
  options.custom.authelia = {
    enable = mkEnableOption "Authelia forward-auth SSO portal, backed by custom.lldap via LDAP";

    subdomain = mkOption {
      type = types.str;
      default = "auth";
      description = "Subdomain for Authelia's own login portal. Never gets its own forward-auth middleware -- see docs/homelab-network.md § Self-Lockout Rule.";
    };

    port = mkOption {
      type = types.port;
      default = 9091;
      description = "Authelia's own listen port (upstream default). Bound to 127.0.0.1 only -- reached through Traefik, and it's also where the forward-auth middleware itself calls back to.";
    };

    ldap = {
      bindDn = mkOption {
        type = types.str;
        default = "uid=authelia,ou=people,${config.custom.lldap.baseDn}";
        description = ''
          Authelia's own LDAP bind user DN. lldap's default search base for
          users is ou=people under the base DN (confirmed against lldap's own
          README § Client Configuration and Authelia's lldap integration
          guide, not assumed) -- this user must exist in lldap
          (custom.lldap.bootstrap.users) and belong to the lldap_strict_readonly
          built-in group, never lldap_admin: Authelia only ever needs to read
          user/group attributes, and scoping the bind account to read-only
          avoids handing a web-facing service full lldap admin rights.
        '';
      };

      bindPasswordFile = mkOption {
        type = types.str;
        description = "Path to an agenix-managed file holding the LDAP bind user's password -- must match custom.lldap.bootstrap.users' matching entry's passwordFile so lldap and Authelia agree on the same credential.";
      };
    };

    jwtSecretFile = mkOption {
      type = types.str;
      description = "Path to an agenix-managed file for Authelia's identity_validation.reset_password.jwt_secret (password-reset flow JWTs).";
    };

    storageEncryptionKeyFile = mkOption {
      type = types.str;
      description = "Path to an agenix-managed file for Authelia's storage.encryption_key (encrypts sensitive fields -- TOTP/WebAuthn secrets -- in its own SQLite database).";
    };

    protectedSubdomains = mkOption {
      type = types.listOf types.str;
      default = [];
      description = ''
        Subdomains (of custom.traefik.acme.domain) that require two-factor
        auth via this Authelia instance -- becomes both an access_control
        rule here and the "authelia@file" middleware on the matching Traefik
        router, wired up by whichever module owns that router (this module
        only builds the middleware and the access_control list; a route
        doesn't get protected until its own router adds
        middlewares = ["authelia@file"], see lib/traefik-route.nix).
        Deliberately never include custom.lldap.subdomain or
        custom.authelia.subdomain themselves -- see § Self-Lockout Rule.
      '';
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = !(builtins.elem config.custom.lldap.subdomain cfg.protectedSubdomains);
          message = "custom.authelia.protectedSubdomains must not include custom.lldap.subdomain -- gating lldap's own admin UI behind Authelia (which authenticates against lldap) risks a total lockout. See docs/homelab-network.md § Self-Lockout Rule.";
        }
        {
          assertion = !(builtins.elem cfg.subdomain cfg.protectedSubdomains);
          message = "custom.authelia.protectedSubdomains must not include custom.authelia.subdomain itself -- Authelia's own portal must stay reachable on its own login, not behind its own forward-auth. See docs/homelab-network.md § Self-Lockout Rule.";
        }
      ];

      services.authelia.instances.main = {
        enable = true;

        secrets = {
          jwtSecretFile = cfg.jwtSecretFile;
          storageEncryptionKeyFile = cfg.storageEncryptionKeyFile;
        };

        # LDAP bind password: not one of nixpkgs' services.authelia.secrets
        # fields (those cover jwt/oidc/session/storage only), so it goes
        # through Authelia's own env-var secret convention instead --
        # confirmed against Authelia's own secrets documentation, which
        # names AUTHENTICATION_BACKEND_LDAP_PASSWORD_FILE explicitly as a
        # real supported secret env var, not guessed. This is a path, not a
        # copied-in secret value, so systemd's LoadCredential machinery
        # doesn't apply here the way it does for the secrets.* fields above --
        # the file itself must be readable by this instance's own system user
        # (authelia-main), which the agenix owner needs to be set to.
        environmentVariables.AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD_FILE = cfg.ldap.bindPasswordFile;

        settings = {
          default_2fa_method = "totp";

          server.address = "tcp://127.0.0.1:${toString cfg.port}/";

          # Duo is explicitly out of scope for this pass -- TOTP and WebAuthn
          # only. No duo_api block here.

          # identity_validation.reset_password.jwt_secret is NOT set here --
          # secrets.jwtSecretFile above maps to
          # AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET_FILE, and
          # Authelia refuses to start if a secret is set both ways (confirmed
          # against Authelia's own secrets documentation).
          authentication_backend.ldap = {
            implementation = "lldap";
            address = "ldap://127.0.0.1:${toString config.custom.lldap.ldapPort}";
            base_dn = config.custom.lldap.baseDn;
            user = cfg.ldap.bindDn;
            # additional_users_dn/additional_groups_dn, users_filter, and
            # groups_filter all default correctly for implementation = lldap
            # (confirmed against Authelia's own lldap integration guide:
            # ou=people / ou=groups search bases, uid/cn attributes) -- not
            # repeated here.
          };

          storage.local.path = "/var/lib/authelia-main/db.sqlite3";

          # No SMTP configured yet -- password-reset/notification emails
          # write to a local file instead of actually sending anything. This
          # is a real gap for the password-reset flow, tracked as a TODO
          # rather than fabricating SMTP credentials that don't exist yet.
          # See hosts/reliant/README.md § Authelia.
          notifier.filesystem.filename = "/var/lib/authelia-main/notification.txt";

          access_control = {
            default_policy = "deny";
            rules =
              map (subdomain: {
                domain = "${subdomain}.${domain}";
                policy = "two_factor";
              })
              cfg.protectedSubdomains;
          };

          session.cookies = [
            {
              inherit domain;
              authelia_url = authUrl;
            }
          ];
        };
      };
    }

    # The forward-auth middleware itself. A router opts in by adding
    # middlewares = ["authelia@file"] (the "@file" suffix is Traefik's own
    # provider tag for anything declared through dynamicConfigOptions, not a
    # literal filename) -- see lib/traefik-route.nix's middlewares parameter.
    # A separate mkIf block from the route registration below: both set
    # services.traefik.dynamicConfigOptions.http, and the module system
    # merges the two attrsets (disjoint subpaths -- .middlewares here,
    # .routers/.services below) the same way dns.nix/home-assistant.nix/
    # zigbee.nix's independent contributions to that same freeform option
    # already coexist; assigning both from a single attrset literal in one
    # module would instead be a plain Nix "attribute already defined" error.
    (mkIf config.custom.traefik.enable {
      services.traefik.dynamicConfigOptions.http.middlewares.authelia.forwardAuth = {
        address = "http://127.0.0.1:${toString cfg.port}/api/authz/forward-auth";
        trustForwardHeader = true;
        authResponseHeaders = ["Remote-User" "Remote-Groups" "Remote-Email" "Remote-Name"];
      };
    })

    # Self-register Traefik route for Authelia's own login portal.
    # Deliberately no authelia middleware on this route either -- see the
    # assertion above and docs/homelab-network.md § Self-Lockout Rule.
    (mkIf config.custom.traefik.enable {
      services.traefik.dynamicConfigOptions.http = mkTraefikRoute {
        name = "authelia";
        subdomain = cfg.subdomain;
        port = cfg.port;
        inherit domain;
      };
    })
  ]);
}
