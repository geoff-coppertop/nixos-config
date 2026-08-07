{
  lib,
  pkgs,
  config,
  ...
}: let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.custom.matter;

  # python-matter-server calls out to the Distributed Compliance Ledger (DCL)
  # and the connectedhomeip Git repo on every startup to (re)fetch current PAA
  # (Product Attestation Authority) root certificates, before the websocket
  # server binds. DCL has been observed serving a certificate that fails
  # strict ASN.1 parsing in the `cryptography` library; that raises an
  # uncaught ValueError inside `paa_certificates.py`, so `server.start()`
  # never completes, the websocket port never opens, and systemd still shows
  # the unit "active (running)" because the process itself doesn't crash. See
  # https://github.com/NixOS/nixpkgs/issues/377136 (open as of 2026-08-07; the
  # nixpkgs revision this flake pins, e2587caef70cea85dd97d7daab492899902dbf5d,
  # carries no workaround for it).
  #
  # Fix: stop fetching PAA certs over the network at all. Ship a static,
  # pinned set of production PAA root certs (the same ones
  # fetch_git_certificates() would otherwise pull from
  # project-chip/connectedhomeip at runtime) baked into the package, and patch
  # `fetch_certificates()` to install those instead of hitting DCL/GitHub.
  # Trade-off: no automatic pickup of newly issued vendor PAA certs — see
  # docs/smart-home.md § Matter for how to re-pin `pinnedPaaCertsRev` below.
  pinnedPaaCertsRev = "94e7e3d2f403a38585dba7bea2cd455267bf8231"; # connectedhomeip master, 2026-08-07
  pinnedPaaCerts = pkgs.fetchgit {
    url = "https://github.com/project-chip/connectedhomeip.git";
    rev = pinnedPaaCertsRev;
    # Makes the fetched derivation *be* this subdirectory (a sparse checkout
    # rooted there), instead of the whole (multi-gigabyte, submodule-laden)
    # connectedhomeip tree.
    rootDir = "credentials/production/paa-root-certs";
    fetchSubmodules = false;
    # TODO: placeholder. `nix build` will fail on the first run and print the
    # real "got: sha256-..." hash to paste in here.
    hash = lib.fakeHash;
  };

  # Only the ~7-line call site in server.py needs to change: it's a small,
  # unique block, so the exact-text match substituteInPlace needs stays easy
  # to keep correct across upstream releases. paa_certificates.py itself
  # (and its now-unreferenced fetch_certificates/fetch_dcl_certificates/
  # fetch_git_certificates functions) is left untouched.
  matterServerPackage = pkgs.python-matter-server.overrideAttrs (oldAttrs: {
    # NOTE: this block is intentionally flush-left (not indented to match
    # its nesting in this file). It's inside a Nix `''...''` string, which
    # strips whatever whitespace is common to every line before handing the
    # text to bash — the embedded Python here relies on its exact 8/12/16/20
    # space indentation to still be valid Python after that stripping, so it
    # is written with zero incidental indentation of its own to strip.
    postPatch =
      (oldAttrs.postPatch or "")
      + ''
substituteInPlace matter_server/server/server.py \
  --replace-fail \
'        # (re)fetch all PAA certificates once at startup
        # NOTE: this must be done before initializing the controller
        await fetch_certificates(
            self.paa_root_cert_dir,
            fetch_test_certificates=self.enable_test_net_dcl,
            fetch_production_certificates=True,
        )' \
'        # Patched by nixos-config (modules/matter.nix): install a
        # pinned, static set of production PAA root certs instead of
        # fetching from DCL/GitHub at startup, which uncaught-ValueErrors
        # on a cert DCL currently serves and keeps the server from ever
        # binding its websocket port. See
        # https://github.com/NixOS/nixpkgs/issues/377136.
        def _install_pinned_paa_certs() -> None:
            self.paa_root_cert_dir.mkdir(parents=True, exist_ok=True)
            for cert_file in sorted(Path("${pinnedPaaCerts}").iterdir()):
                if cert_file.suffix in (".pem", ".der"):
                    (self.paa_root_cert_dir / cert_file.name).write_bytes(
                        cert_file.read_bytes()
                    )

        await self.loop.run_in_executor(None, _install_pinned_paa_certs)'
      '';
  });
in {
  options.custom.matter = {
    enable = mkEnableOption "python-matter-server for Home Assistant's Matter integration";
  };

  config = mkIf cfg.enable {
    # python-matter-server: the Matter controller/fabric that Home Assistant's
    # "matter" integration (listed in the host's extraComponents) connects to
    # over WebSocket at ws://localhost:5580/ws. Adding the integration in the
    # UI and commissioning each Matter device with its pairing code — here the
    # Aqara M2 hub, which bridges the U100 locks (and later the office FP1e
    # presence sensor) — are one-time UI steps; enabling the server just
    # installs the backend HA talks to. Runs on the same host as HA (defiant),
    # so HA reaches it over localhost.
    services.matter-server.enable = true;
    services.matter-server.package = matterServerPackage;
  };
}
