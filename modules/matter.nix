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
    hash = "sha256-XCrCYJMbU4SHnQfsqhPoA8GQbSahucQz4qVzETyVHKM=";
  };

  # A small, standalone regression test for the patch below: calls the
  # patched fetch_certificates() directly with a tmp_path and asserts it
  # actually installs the pinned certs, with no network and no dependency on
  # server.py/zeroconf. This exists because the *only* upstream test that
  # exercises fetch_certificates() at all is test_server_start (via
  # server.start()), which we have to deselect below for an unrelated
  # reason (see disabledTests) — without this file, the patched function
  # would have zero automated coverage.
  paaCertificatesPinnedTest = pkgs.writeText "test_paa_certificates_pinned.py" ''
    """Regression test for nixos-config's pinned-PAA-certs patch (modules/matter.nix)."""

    from pathlib import Path

    import pytest

    from matter_server.server.helpers.paa_certificates import fetch_certificates


    @pytest.mark.asyncio
    async def test_fetch_certificates_installs_pinned_certs(tmp_path: Path) -> None:
        """fetch_certificates() should copy the pinned certs, not hit the network."""
        target_dir = tmp_path / "certs"
        count = await fetch_certificates(target_dir)
        installed = sorted(p.name for p in target_dir.iterdir())
        assert count == len(installed)
        assert count > 0
        assert all(p.suffix in (".pem", ".der") for p in target_dir.iterdir())
  '';

  # Patches fetch_certificates() itself (in paa_certificates.py), not its
  # call site in server.py: it's the actual top-level, importable function,
  # so patching here is both a smaller/more robust substituteInPlace match
  # (the function's exact text is far less likely to shift across upstream
  # releases than a partial call-site snippet) and lets
  # paaCertificatesPinnedTest above exercise it directly.
  matterServerPackage = pkgs.python-matter-server.overrideAttrs (oldAttrs: {
    # Overriding postPatch changes this derivation's hash, so it can no
    # longer be pulled prebuilt from cache.nixos.org and gets built (and
    # test-suite-checked) locally/in CI instead — which surfaced a failure
    # unrelated to this patch: test_server_start calls server.start(), which
    # (regardless of how PAA certs get installed) goes on to
    # device_controller.start(), where zeroconf's IPV6_MULTICAST_IF socket
    # setup raises "OSError: [Errno 92] Protocol not available" — no real
    # IPv6 multicast networking in the build sandbox on this host
    # (aarch64/defiant). This package's full test suite otherwise passes on
    # nixpkgs's own Hydra, so this is one observed failure on this build
    # host, not a general "sandboxes can't do multicast" fact. Deselect only
    # this test — doCheck stays on, and paaCertificatesPinnedTest above
    # covers the actual patched function directly instead.
    disabledTests = (oldAttrs.disabledTests or []) ++ ["test_server_start"];

    postPatch =
      (oldAttrs.postPatch or "")
      + ''
        cp ${paaCertificatesPinnedTest} tests/server/test_paa_certificates_pinned.py

        substituteInPlace matter_server/server/helpers/paa_certificates.py \
          --replace-fail \
        'async def fetch_certificates(
            paa_root_cert_dir: Path,
            fetch_test_certificates: bool = True,
            fetch_production_certificates: bool = True,
        ) -> int:
            """Fetch PAA Certificates."""
            loop = asyncio.get_running_loop()
            paa_root_cert_dir_version = paa_root_cert_dir / ".version"

            def _check_paa_root_dir(
                paa_root_cert_dir: Path, paa_root_cert_dir_version: Path
            ) -> datetime | None:
                """Return timestamp of last fetch or None if a initial download is required."""
                if paa_root_cert_dir.is_dir():
                    if paa_root_cert_dir_version.exists():
                        stat = paa_root_cert_dir_version.stat()
                        return datetime.fromtimestamp(stat.st_mtime, tz=UTC)

                    # Old certificate store version, delete all files
                    LOGGER.info("Old PAA root certificate store found, removing certificates.")
                    for path in paa_root_cert_dir.iterdir():
                        if not path.is_dir():
                            path.unlink()
                else:
                    paa_root_cert_dir.mkdir(parents=True)
                return None

            last_fetch = await loop.run_in_executor(
                None, _check_paa_root_dir, paa_root_cert_dir, paa_root_cert_dir_version
            )
            if last_fetch and last_fetch > datetime.now(tz=UTC) - timedelta(days=1):
                LOGGER.info("Skip fetching certificates (already fetched within the last 24h).")
                return 0

            total_fetch_count = 0

            LOGGER.info("Fetching the latest PAA root certificates from DCL.")

            # Determine which url'"'"'s need to be queried.
            if fetch_production_certificates:
                fetch_count = await fetch_dcl_certificates(
                    paa_root_cert_dir=paa_root_cert_dir,
                    base_name="dcld_production_",
                    base_url=DCL_PRODUCTION_URL,
                )
                LOGGER.info("Fetched %s PAA root certificates from DCL.", fetch_count)
                total_fetch_count += fetch_count

            if fetch_test_certificates:
                fetch_count = await fetch_dcl_certificates(
                    paa_root_cert_dir=paa_root_cert_dir,
                    base_name="dcld_test_",
                    base_url=DCL_TEST_URL,
                )
                LOGGER.info("Fetched %s PAA root certificates from Test DCL.", fetch_count)
                total_fetch_count += fetch_count

            if fetch_test_certificates:
                total_fetch_count += await fetch_git_certificates(paa_root_cert_dir)
            else:
                # Treat the Chip-Test certificates as production, we use them in our examples
                total_fetch_count += await fetch_git_certificates(
                    paa_root_cert_dir, "Chip-Test"
                )

            await loop.run_in_executor(None, paa_root_cert_dir_version.write_text, "1")

            return fetch_count' \
        'async def fetch_certificates(
            paa_root_cert_dir: Path,
            fetch_test_certificates: bool = True,
            fetch_production_certificates: bool = True,
        ) -> int:
            """Install a pinned, static set of production PAA root certs.

            Patched by nixos-config (modules/matter.nix): the live DCL/GitHub
            fetch this function used to perform crashes on a certificate DCL
            currently serves (uncaught ValueError from strict ASN.1 parsing
            in `cryptography`). See
            https://github.com/NixOS/nixpkgs/issues/377136.
            """
            loop = asyncio.get_running_loop()

            def _install_pinned_certs() -> int:
                paa_root_cert_dir.mkdir(parents=True, exist_ok=True)
                count = 0
                for cert_file in sorted(Path("${pinnedPaaCerts}").iterdir()):
                    if cert_file.suffix in (".pem", ".der"):
                        (paa_root_cert_dir / cert_file.name).write_bytes(
                            cert_file.read_bytes()
                        )
                        count += 1
                return count

            return await loop.run_in_executor(None, _install_pinned_certs)'
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
