{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkMerge mkOption types;
  mkTraefikRoute = import ../lib/traefik-route.nix;
  cfg = config.custom.authelia;
  inherit (config.custom.traefik.acme) domain;
  authUrl = "https://${cfg.subdomain}.${domain}/";

  # Home Assistant's OIDC client entry, as a whole settingsFile rather than
  # part of the regular Nix-rendered `settings` attrset -- client_secret has
  # to be substituted in at runtime (Authelia's own Go-template config
  # filter, the "secret" function reading an absolute path directly, exactly
  # the way the jwks private key doc example does it) rather than baked into
  # the world-readable Nix store, and Authelia's config-file merging replaces
  # whole list values (identity_providers.oidc.clients is a list) rather than
  # merging list items -- so the entire client entry has to live in one file.
  # `{{ secret ... | mindent N "|" | msquote }}` is written with no manual
  # surrounding quotes, exactly matching Authelia's own jwks "key" doc
  # example -- msquote already produces a correctly-quoted YAML scalar, so
  # adding our own quotes around the whole template expression would
  # double-quote it. Field values (client_id, redirect_uris, scopes,
  # response/grant types, token_endpoint_auth_method) confirmed against
  # Authelia's own Home Assistant OIDC integration guide
  # (authelia.com/integration/openid-connect/clients/home-assistant), not
  # guessed.
  homeAssistantOidcClientFile = pkgs.writeText "authelia-oidc-client-home-assistant.yml" ''
    identity_providers:
      oidc:
        clients:
          - client_id: '${cfg.oidc.homeAssistant.clientId}'
            client_name: 'Home Assistant'
            client_secret: {{ secret "${cfg.oidc.homeAssistant.clientSecretHashFile}" | mindent 12 "|" | msquote }}
            public: false
            require_pkce: true
            pkce_challenge_method: 'S256'
            authorization_policy: 'two_factor'
            redirect_uris:
              - '${cfg.oidc.homeAssistant.redirectUri}'
            scopes:
              - 'openid'
              - 'profile'
              - 'groups'
            response_types:
              - 'code'
            grant_types:
              - 'authorization_code'
            access_token_signed_response_alg: 'none'
            userinfo_signed_response_alg: 'none'
            token_endpoint_auth_method: 'client_secret_post'
  '';
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

    oidc = {
      enable = mkEnableOption ''
        Authelia as an OpenID Connect 1.0 provider -- a separate Authelia
        capability from the LDAP-backed forward-auth above, for services that
        already have their own real login (so forward-auth would just add a
        redundant second login in front of it). See
        docs/homelab-network.md § OIDC Provider.
      '';

      issuerPrivateKeyFile = mkOption {
        type = types.str;
        description = ''
          Path to an agenix-managed PEM file holding Authelia's OIDC issuer
          signing key -- an RSA private key, PKCS#8 or PKCS#1 encoded, at
          least 2048 bits (confirmed against Authelia's own OpenID Connect
          1.0 Provider configuration docs, "jwks" § "key"). Maps to
          services.authelia.instances.main.secrets.oidcIssuerPrivateKeyFile,
          which nixpkgs' authelia module auto-templates into
          identity_providers.oidc.jwks at startup via its own Go-template
          config filter -- jwks is never set directly in settings here.
          Generate with:
            openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048
        '';
      };

      hmacSecretFile = mkOption {
        type = types.str;
        description = ''
          Path to an agenix-managed file holding Authelia's OIDC HMAC secret
          (identity_providers.oidc.hmac_secret), used to sign OIDC JWTs --
          Authelia's own docs recommend a random alphanumeric string of 64+
          characters. Maps to
          services.authelia.instances.main.secrets.oidcHmacSecretFile.
          Generate with:
            openssl rand -base64 64 | tr -d '\n=+/' | head -c 64
        '';
      };

      homeAssistant = {
        enable = mkEnableOption ''
          Registering Home Assistant as an OIDC client of this Authelia
          instance, for real SSO via the third-party hass-oidc-auth HACS
          component -- see Authelia's own Home Assistant OIDC integration
          guide (authelia.com/integration/openid-connect/clients/home-assistant).
          Requires custom.authelia.oidc.enable.
        '';

        clientId = mkOption {
          type = types.str;
          default = "home-assistant";
          description = ''
            OIDC client_id. Home Assistant's hass-oidc-auth integration
            (auth_oidc.client_id in configuration.yaml) must be configured
            with this same value.
          '';
        };

        redirectUri = mkOption {
          type = types.str;
          default = "https://home.${domain}/auth/oidc/callback";
          description = ''
            Home Assistant's OIDC callback URL -- hass-oidc-auth's fixed
            callback path (/auth/oidc/callback, confirmed against Authelia's
            own Home Assistant integration guide) at whatever subdomain
            modules/home-assistant.nix's Traefik route hardcodes ("home",
            not itself a configurable option there). Not consumed by Home
            Assistant's own config (hass-oidc-auth derives its callback URL
            from HA's own base URL) -- this is what Authelia's client
            registration expects to receive the browser back on.
          '';
        };

        clientSecretHashFile = mkOption {
          type = types.str;
          description = ''
            Path to an agenix-managed file holding Authelia's own
            pbkdf2-sha512 *hash* of Home Assistant's OIDC client secret --
            NOT the raw secret itself. Authelia's
            identity_providers.oidc.clients[].client_secret field stores only
            the digest it validates an incoming secret against (confirmed
            against Authelia's own OpenID Connect 1.0 Clients configuration
            docs) -- there is no oidcClientSecretFile in nixpkgs'
            services.authelia secrets.* fields, so this is read directly at
            runtime via Authelia's own Go-template "secret" function in a
            generated settingsFile below, the same way
            custom.authelia.ldap.bindPasswordFile is read directly rather
            than through systemd LoadCredential.

            Generate both the raw secret and its digest together with the
            authelia package's own CLI:
              nix run nixpkgs#authelia -- crypto hash generate pbkdf2 --variant sha512 --random
            This prints a random plaintext secret (goes into Home Assistant's
            own auth_oidc.client_secret -- not managed by this repo) and its
            digest (goes into this file, and only this file).
          '';
        };
      };
    };

    notifier.smtp = {
      enable = mkEnableOption ''
        Sending Authelia's password-reset/identity-verification and other
        notification emails over real SMTP, instead of the filesystem-stub
        fallback (notifier.filesystem, which just writes to a local file and
        never actually delivers anything). See docs/homelab-network.md §
        Authelia.
      '';

      address = mkOption {
        type = types.str;
        description = ''
          Authelia's notifier.smtp.address, a URI-scheme value, e.g.
          "submission://smtp-relay.brevo.com:587" -- confirmed against
          Authelia's own SMTP notifier configuration docs, current version:
          this field takes a URI (scheme selects the connection mode --
          "submission" is STARTTLS on 587, "submissions" would be implicit
          TLS on 465, "smtp" plaintext), not a bare host:port pair.
        '';
      };

      username = mkOption {
        type = types.str;
        description = ''
          SMTP AUTH username for notifier.smtp.username. For Brevo's
          transactional relay this is NOT the account's login email --
          confirmed live (a real switch got "535 5.7.8 Authentication
          failed" using the account email here) -- it's the distinct
          generated "Login" value shown on Settings > SMTP & API > SMTP tab
          (format <id>@smtp-brevo.com), separate from the email used to sign
          into app.brevo.com.
        '';
      };

      sender = mkOption {
        type = types.str;
        description = ''
          Authelia's notifier.smtp.sender (required whenever notifier.smtp is
          used) -- an RFC5322-formatted From address, e.g.
          "Authelia <no-reply@example.com>".
        '';
      };

      passwordFile = mkOption {
        type = types.str;
        description = ''
          Path to an agenix-managed file holding the SMTP AUTH password (a
          provider-issued SMTP key, e.g. Brevo's "SMTP key" -- not the
          account password or a general API key). Confirmed against
          nixpkgs' services.authelia.instances.<name>.secrets submodule
          (nixos/modules/services/security/authelia.nix): the only named
          secrets are jwtSecretFile, oidcIssuerPrivateKeyFile,
          oidcHmacSecretFile, sessionSecretFile, and
          storageEncryptionKeyFile -- there is no smtpPasswordFile, and
          plain YAML has no notifier.smtp.password_file key either
          (confirmed against Authelia's own SMTP notifier docs). So this
          goes through Authelia's own env-var secret convention instead,
          the same way custom.authelia.ldap.bindPasswordFile does:
          environmentVariables.AUTHELIA_NOTIFIER_SMTP_PASSWORD_FILE.
        '';
      };
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
        {
          assertion = !cfg.oidc.homeAssistant.enable || cfg.oidc.enable;
          message = "custom.authelia.oidc.homeAssistant.enable requires custom.authelia.oidc.enable -- Home Assistant's OIDC client registration only makes sense once this Authelia instance actually runs as an OIDC provider.";
        }
      ];

      # Confirmed live on a real switch: authelia-main only depended on
      # lldap.service being up, not on lldap-bootstrap.service having
      # actually finished reconciling the "authelia" bind account it logs in
      # with -- on a real deploy this raced and crash-looped twice
      # ("connection refused" while lldap was still starting, then "Invalid
      # Credentials" while bootstrap.sh was still mid-run) before systemd's
      # restart policy got it up on the third try. Blocking on
      # lldap-bootstrap.service explicitly (a "Type = oneshot" unit that
      # only reports done once bootstrap.sh actually exits) removes the
      # race instead of relying on Restart=on-failure to paper over it.
      systemd.services.authelia-main = {
        after = ["lldap-bootstrap.service"];
        wants = ["lldap-bootstrap.service"];
      };

      services.authelia.instances.main = {
        enable = true;

        secrets = {
          inherit (cfg) jwtSecretFile storageEncryptionKeyFile;
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
        environmentVariables = mkMerge [
          {
            AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD_FILE = cfg.ldap.bindPasswordFile;
          }
          (mkIf cfg.notifier.smtp.enable {
            # SMTP AUTH password: not one of nixpkgs' services.authelia.secrets
            # fields either (see custom.authelia.notifier.smtp.passwordFile's
            # own doc comment above for why), so it goes through this same
            # env-var convention.
            AUTHELIA_NOTIFIER_SMTP_PASSWORD_FILE = cfg.notifier.smtp.passwordFile;
          })
        ];

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

          # notifier.smtp.password is deliberately absent here -- plain YAML
          # has no notifier.smtp.password_file key (confirmed against
          # Authelia's own SMTP notifier docs), and it isn't one of nixpkgs'
          # services.authelia.secrets fields either, so it's set via
          # environmentVariables.AUTHELIA_NOTIFIER_SMTP_PASSWORD_FILE above
          # instead -- see custom.authelia.notifier.smtp.passwordFile's own
          # doc comment for the full reasoning.
          notifier = mkMerge [
            (mkIf cfg.notifier.smtp.enable {
              smtp = {
                inherit (cfg.notifier.smtp) address username sender;
              };
            })
            # Fallback when no real SMTP relay is configured: writes
            # password-reset/notification emails to a local file instead of
            # actually sending them. Fine for a dev/test instance, but a real
            # gap for the password-reset flow on anything reachable by an
            # actual household -- see custom.authelia.notifier.smtp.enable.
            (mkIf (!cfg.notifier.smtp.enable) {
              filesystem.filename = "/var/lib/authelia-main/notification.txt";
            })
          ];

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

    # Authelia as an OpenID Connect 1.0 provider -- a separate capability
    # from the LDAP-backed forward-auth above, both running from the same
    # instance simultaneously. A separate mkIf/mkMerge entry (rather than
    # folded into the block above) for the same reason the forward-auth
    # middleware below is split out: this only applies when
    # custom.authelia.oidc.enable is set, independent of the base
    # cfg.enable gate this whole mkMerge list is already under.
    (mkIf cfg.oidc.enable {
      services.authelia.instances.main = {
        secrets = {
          oidcIssuerPrivateKeyFile = cfg.oidc.issuerPrivateKeyFile;
          oidcHmacSecretFile = cfg.oidc.hmacSecretFile;
        };

        # Home Assistant's client entry (client_secret and all) lives
        # entirely in its own generated settingsFile -- see
        # homeAssistantOidcClientFile's own comment above for why it can't
        # be split between this settings attrset and a secret-only fragment.
        # No identity_providers.oidc.jwks here: nixpkgs' authelia module
        # auto-generates that from secrets.oidcIssuerPrivateKeyFile above via
        # its own Go-template settingsFile, merged in alongside these.
        settingsFiles = mkIf cfg.oidc.homeAssistant.enable [homeAssistantOidcClientFile];
      };
    })

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
        inherit (cfg) subdomain port;
        inherit domain;
      };
    })
  ]);
}
