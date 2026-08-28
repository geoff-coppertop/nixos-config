#!/usr/bin/env python3
"""
ha_config_check.py

Validate a host's Nix-declared Home Assistant automations and input_datetime
helpers against Home Assistant's own config schema, via `hass --script
check_config`.

Nix serializes services.home-assistant.config verbatim — it has no idea what
a valid HA trigger platform, action shape, or service name is, so a malformed
automation (bad trigger platform, broken choose/action, unknown service)
passes `nix flake check` and the toplevel build untouched and only breaks
when Home Assistant loads it at runtime. This script closes that gap in CI by
actually running HA's real config loader against the rendered config, without
needing a live instance.

Building blocks, all defined per-host under `packages.<system>` in flake.nix:
  ha-config-<host>   this host's "automation manual" + input_datetime content,
                      rendered to a standalone configuration.yaml
  ha-check-hass       reliant's deployed home-assistant package,
                      extraComponents and all. The check itself only needs
                      core triggers/actions, but ci_ha_config_changed.py
                      diffs this derivation to decide whether to run at all,
                      and bare pkgs.home-assistant is invariant under
                      extraComponents changes.
  ha-check-colorlog   colorlog, pinned to the exact version HA's own
                      `--script` runner requires

The colorlog pin needs explaining. homeassistant/scripts/__init__.py's `run()`
unconditionally checks each script's REQUIREMENTS before running it, and
homeassistant/scripts/check_config.py pins REQUIREMENTS = ("colorlog==6.10.1",)
— an exact-version match, not a floor. If that exact version isn't already
importable, it shells out to `sys.executable -m uv pip install`. That install
cannot work here: nixpkgs' Python interpreters carry an EXTERNALLY-MANAGED
marker, and uv refuses outright to touch the read-only /nix/store, regardless
of --target (confirmed live: "tries to modify the immutable /nix/store
filesystem"). Nor is pointing at nixpkgs' own `colorlog` package reliable —
it tracks upstream colorlog releases, not HA's specific pin, and has already
drifted (nixpkgs shipped 6.11.0 while HA still required 6.10.1 exactly).
ha-check-colorlog instead builds 6.10.1 directly from its PyPI wheel, so
is_installed() is satisfied and install_package() never runs. This script
puts it on PYTHONPATH when invoking hass — the NixOS module normally supplies
this kind of runtime extra via passthru.pythonPath on the systemd service;
this script has no service, so it hands colorlog to hass the same way
directly.

Usage:
    python3 tools/ha_config_check.py <host> [--system <nix-system>]
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from common import die, repo_root


def nix_build(attr: str, root: Path) -> str:
    """Run `nix build --no-link --print-out-paths <attr>`, returning the store path.

    Exits the process on failure. There is nothing useful this script can do
    without these artifacts, and nix's own stderr already explains why.
    """
    result = subprocess.run(
        ["nix", "build", "--no-link", "--print-out-paths", attr],
        capture_output=True,
        text=True,
        cwd=str(root),
    )
    if result.returncode != 0:
        die(f"nix build {attr} failed:\n{result.stderr.strip()}")
    return result.stdout.strip()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "host",
        help="Host whose ha-config-<host> flake output to validate, e.g. reliant.",
    )
    parser.add_argument(
        "--system",
        default="x86_64-linux",
        help=(
            "Nix system the flake's packages.<system> outputs are built "
            "under (default: x86_64-linux)."
        ),
    )
    args = parser.parse_args()

    root = repo_root()
    if root is None:
        die("must be run from within the nixos-config git repository")

    hass = nix_build(f".#packages.{args.system}.ha-check-hass", root)
    colorlog = nix_build(f".#packages.{args.system}.ha-check-colorlog", root)
    conf = nix_build(f".#packages.{args.system}.ha-config-{args.host}", root)

    site_packages = sorted(Path(colorlog).glob("lib/python*/site-packages"))
    if not site_packages:
        die(f"no lib/python*/site-packages found under {colorlog}")

    work = Path(tempfile.mkdtemp(prefix="ha-config-check-"))
    dest = work / "configuration.yaml"
    shutil.copy(conf, dest)
    dest.chmod(0o600)

    env = os.environ.copy()
    # HA's script runner writes its fault log and (were is_installed to ever
    # fail again) any install target under here — must be writable, and
    # separate from a real HA install's actual config dir.
    env["HOME"] = str(work)
    env["PYTHONPATH"] = str(site_packages[0])

    result = subprocess.run(
        [str(Path(hass) / "bin" / "hass"), "--script", "check_config", "-c", str(work)],
        env=env,
    )
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
