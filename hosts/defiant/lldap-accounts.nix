{...}: {
  # Declarative lldap accounts for defiant's directory (custom.lldap.enable),
  # reconciled against the live server on every rebuild by bootstrap.sh — see
  # modules/lldap.nix and docs/homelab-network.md § Authelia/lldap SSO.
  #
  # Only the Authelia service account is populated here. The household's real
  # user accounts (thomasga and whoever else needs SSO login) are
  # intentionally NOT filled in with placeholder data — that's real people's
  # usernames/emails, not something to fabricate. Add each one as its own
  # entry below before enabling custom.authelia.protectedSubdomains against a
  # live route, following the same shape as the authelia entry:
  #
  #   thomasga = {
  #     id = "thomasga";
  #     email = "<real address>";
  #     groups = ["household"];
  #   };
  #
  # No password_file for household users — they set their own password
  # through lldap's own web UI (https://ad.coppertop.ca) on first login, the
  # same way any self-service account provisioning works. password_file is
  # only for service accounts like Authelia's bind user below, where both
  # sides of the bind must agree on a password without a manual step.
  custom.lldap = {
    groups.household = {name = "household";};

    users.authelia = {
      id = "authelia";
      email = "authelia@coppertop.ca";
      # Same secret Authelia's own custom.authelia.ldap.bindPasswordFile
      # points at — both sides of the LDAP bind need to agree, and
      # bootstrap.sh setting the password declaratively (confirmed via
      # bootstrap.md: the password/password_file field is settable, not
      # read-only) closes what would otherwise be a manual one-time step.
      password_file = "/run/agenix/authelia/lldap-bind-password";
      groups = [];
    };
  };
}
