{
  config,
  lib,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkMerge mkOption types;
  mkTraefikRoute = import ../lib/traefik-route.nix;
  cfg = config.custom.authelia;
  inherit (config.custom.traefik.acme) domain;
  instanceName = "main";
  autheliaService = "authelia-${instanceName}";

  # lldap's own fixed schema (not configurable, same assumption
  # modules/lldap.nix makes): users live under ou=people beneath the base DN.
  bindDn = "uid=${cfg.ldap.bindUsername},ou=people,${cfg.ldap.baseDn}";
in {
  options.custom.authelia = {
    enable = mkEnableOption "Authelia forward-auth SSO portal, backed by lldap";

    subdomain = mkOption {
      type = types.str;
      default = "auth";
      description = "Subdomain for Authelia's own portal.";
    };

    ldap = {
      baseDn = mkOption {
        type = types.str;
        example = "dc=coppertop,dc=ca";
        description = "Base DN of the lldap directory to authenticate against.";
      };

      bindUsername = mkOption {
        type = types.str;
        default = "authelia";
        description = ''
          lldap username of the read-only service account Authelia binds as.
          Expected to be declared in custom.lldap.users with a
          password_file pointing at the same secret as
          custom.authelia.ldap.bindPasswordFile, so bootstrap.sh and
          Authelia's own config agree on the account's password without a
          manual step.
        '';
      };

      bindPasswordFile = mkOption {
        type = types.str;
        description = "Path to a file containing the LDAP bind account's password (agenix-managed).";
      };
    };

    protectedSubdomains = mkOption {
      type = types.listOf types.str;
      default = [];
      example = ["dns1" "dns2" "home" "zigbee"];
      description = ''
        Subdomains gated behind Authelia's two_factor policy in
        access_control.rules. Listing a subdomain here only covers
        Authelia's side of the gate — the corresponding Traefik router
        still needs `middlewares = ["authelia"];` attached (via
        mkTraefikRoute where this repo owns the calling module, or from
        the host's configuration.nix the way hosts/defiant/configuration.nix's
        dns2 router is hand-added, where it doesn't). A subdomain listed
        here without the middleware attached does nothing; a subdomain with
        the middleware attached but not listed here falls through to
        access_control's default_policy (deny) and locks everyone out,
        including on successful login.
      '';
    };

    secrets = {
      jwtSecretFile = mkOption {
        type = types.str;
        description = "Path to Authelia's JWT secret, used during identity verification (agenix-managed).";
      };

      storageEncryptionKeyFile = mkOption {
        type = types.str;
        description = "Path to Authelia's storage encryption key, e.g. TOTP secrets/WebAuthn credentials at rest (agenix-managed).";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      services.authelia.instances.${instanceName} = {
        enable = true;

        secrets = {
          jwtSecretFile = cfg.secrets.jwtSecretFile;
          storageEncryptionKeyFile = cfg.secrets.storageEncryptionKeyFile;
          # No sessionSecretFile: that secret is only consumed by the redis
          # session provider. This deployment uses the default in-memory
          # session provider (single Authelia instance, single node) —
          # sessions don't survive an authelia-main restart, meaning an
          # occasional forced re-login, which is an accepted tradeoff
          # against standing up redis for one household's worth of load.
        };

        # Authelia's LDAP bind password isn't one of the typed secrets.*File
        # options above (only jwt/oidc/session/storageEncryption are) — it
        # uses Authelia's generic <PATH>_FILE secrets convention instead
        # (https://www.authelia.com/c/secrets), read directly by the
        # authelia-main process itself rather than loaded by systemd, so
        # (unlike jwtSecretFile/storageEncryptionKeyFile, which go through
        # LoadCredential and can stay root-only) this secret file must be
        # readable by the authelia-main user — flagged in the secrets list
        # handed to secrets-warden.
        environmentVariables = {
          AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD_FILE = cfg.ldap.bindPasswordFile;
        };

        settings = {
          default_2fa_method = "totp";

          server.address = "tcp://127.0.0.1:9091/";

          authentication_backend.ldap = {
            address = "ldap://127.0.0.1:${toString config.custom.lldap.ldapPort}";
            implementation = "lldap";
            base_dn = cfg.ldap.baseDn;
            user = bindDn;
          };

          # Duo is deferred, not cancelled: TOTP/WebAuthn are the only 2FA
          # methods configured for this pass. Adding Duo later means a
          # duo_api block here plus integration_key/secret_key secrets,
          # neither of which exist yet.

          access_control = {
            default_policy = "deny";
            rules =
              map (sub: {
                domain = "${sub}.${domain}";
                policy = "two_factor";
              })
              cfg.protectedSubdomains;
          };

          session.cookies = [
            {
              inherit domain;
              authelia_url = "https://${cfg.subdomain}.${domain}";
            }
          ];

          storage.local.path = "/var/lib/${autheliaService}/db.sqlite3";

          # No SMTP relay exists anywhere in this repo (no external SaaS
          # dependency to stand one up for). Password-reset/identity-
          # verification emails land in a local file instead of being
          # mailed — read via SSH. Acceptable for a household-scale
          # deployment; revisit if that friction turns out to matter.
          notifier.filesystem.filename = "/var/lib/${autheliaService}/notification.txt";
        };
      };
    }

    (mkIf config.custom.traefik.enable {
      services.traefik.dynamicConfigOptions.http = mkMerge [
        (mkTraefikRoute {
          name = "authelia";
          subdomain = cfg.subdomain;
          port = 9091;
          inherit domain;
          # Deliberately NOT behind its own middleware — the same
          # self-lockout class of bug flagged on modules/lldap.nix's route:
          # Authelia can't gate access to its own login portal.
        })
        {
          # Reusable forward-auth middleware other routes opt into with
          # `middlewares = ["authelia"];` in their own mkTraefikRoute call
          # (or, for routes this repo can't edit the owning module of, from
          # the host configuration.nix the same way hosts/defiant/
          # configuration.nix's dns2 router is hand-added — see
          # docs/homelab-network.md § Traefik Route Registration).
          middlewares.authelia.forwardAuth = {
            # 127.0.0.1, not localhost — same loopback invariant as
            # lib/traefik-route.nix itself (see the comment there): a
            # strict trust check on the receiving end can reject a request
            # that arrives over ::1.
            address = "http://127.0.0.1:9091/api/verify";
            trustForwardHeader = true;
            authResponseHeaders = ["Remote-User" "Remote-Groups" "Remote-Email" "Remote-Name"];
          };
        }
      ];
    })
  ]);
}
