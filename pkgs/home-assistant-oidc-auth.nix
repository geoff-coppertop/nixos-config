# The third-party "hass-oidc-auth" Home Assistant integration
# (github.com/christiaangoossens/hass-oidc-auth), installed via
# services.home-assistant.customComponents rather than extraComponents --
# same reasoning as pkgs/home-assistant-wiim.nix: it is a third-party
# custom_components (HACS) package, not part of Home Assistant core, so
# nixpkgs' component-packages.nix has no entry for it. Its manifest.json
# domain is "auth_oidc", matching the `auth_oidc:` configuration.yaml key
# this backs (custom.home-assistant.oidc in modules/home-assistant.nix). See
# docs/smart-home.md § OIDC Login (Authelia SSO) and
# docs/homelab-network.md § OIDC Provider for the full design.
{
  lib,
  buildHomeAssistantComponent,
  fetchFromGitHub,
  home-assistant,
}:
buildHomeAssistantComponent rec {
  owner = "christiaangoossens";
  domain = "auth_oidc";
  version = "1.2.1";

  src = fetchFromGitHub {
    inherit owner;
    repo = "hass-oidc-auth";
    tag = "v${version}";
    # Real NAR hash, from the hash-mismatch error a real `nix build` reported
    # against the lib.fakeHash placeholder this was originally written with.
    hash = "sha256-vwQDrMM4phbrXT85Syyz6hWEIhLB3TKNNTM04OdvNWk=";
  };

  # manifest.json's own "requirements": aiofiles, jinja2, joserfc. Real build
  # error corrected the assumption this comment originally made: jinja2
  # being a hard dependency of Home Assistant core itself doesn't satisfy
  # buildHomeAssistantComponent's own manifestCheckPhase, which verifies
  # every manifest.json requirement against *this derivation's own*
  # `dependencies`, not HA's eventual merged environment -- omitting it
  # failed a real `nix build` with "jinja2 not installed". All three
  # (aiofiles, jinja2, joserfc) exist as ordinary top-level nixpkgs
  # python-modules, confirmed against nixpkgs' own tree, so they resolve
  # directly off home-assistant.python3Packages without a hand-written
  # package file (no pywiim-style gap here).
  dependencies = with home-assistant.python3Packages; [
    aiofiles
    jinja2
    joserfc
  ];

  meta = {
    description = "OpenID Connect (OIDC) client/relying-party integration for Home Assistant";
    homepage = "https://github.com/christiaangoossens/hass-oidc-auth";
    changelog = "https://github.com/christiaangoossens/hass-oidc-auth/releases/tag/v${version}";
    license = lib.licenses.mit;
  };
}
