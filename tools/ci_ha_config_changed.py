#!/usr/bin/env python3
"""
ci_ha_config_changed.py

Decide whether reliant's Home Assistant config-check actually needs to
re-run, by diffing the derivations it depends on rather than assuming every
reliant change touches Home Assistant.

`ha-config-check` (see tools/ha_config_check.py) validates two things: the
rendered automation/input_datetime config (packages.<system>.ha-config-reliant)
and the Home Assistant package itself plus its check_config dependency
(packages.<system>.ha-check-hass, packages.<system>.ha-check-colorlog) — the
latter pair changes on a nixpkgs bump even when no automation file moved, and
ha-check-hass is reliant's *deployed* HA package, so it also changes when
custom.home-assistant.extraComponents changes. Both are still worth
re-validating. If none of the three drvPaths differ
between base and head, nothing the check exercises has changed.

This script is only meant to run once the caller already knows reliant's
toplevel changed (the `changes` job's derivation-diff) — reliant's toplevel
being identical between base and head already implies these three are too,
so there is no point calling this otherwise. Hardcoded to reliant: it is the
only host with Home Assistant enabled today, and generalizing to discover
HA-enabled hosts has no second host to justify it yet.

Fails safe everywhere, matching ci_changed_hosts.py's posture: any
eval/checkout problem is treated as "changed" rather than risking a skipped
validation.

Prints `true` or `false` as a single line on stdout, for the workflow to
capture into $GITHUB_OUTPUT.

Usage:
    python3 tools/ci_ha_config_changed.py --base <sha> --head <sha> [--system <nix-system>]
"""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from common import checkout, ci_log, commit_exists, nix_eval_json, repo_root

# The three flake packages tools/ha_config_check.py builds to run the check.
# A change to any one of them means the check's result could differ.
PACKAGES = ["ha-config-reliant", "ha-check-hass", "ha-check-colorlog"]

DRVPATH_EXPR = "pkg: builtins.unsafeDiscardStringContext pkg.drvPath"


def package_drvpaths(system: str, root: Path) -> dict[str, str] | None:
    """drvPath of each package in PACKAGES at the current checkout, or None."""
    drvpaths = {}
    for pkg in PACKAGES:
        drvpath = nix_eval_json(f".#packages.{system}.{pkg}", DRVPATH_EXPR, root)
        if not isinstance(drvpath, str) or not drvpath:
            return None
        drvpaths[pkg] = drvpath
    return drvpaths


def evaluate_at(sha: str, system: str, root: Path) -> dict[str, str] | None:
    """Check out sha and evaluate all three package drvPaths there."""
    if not checkout(sha, root):
        return None
    return package_drvpaths(system, root)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default="", help="base commit SHA of the push or PR")
    parser.add_argument("--head", required=True, help="head commit SHA of the push or PR")
    parser.add_argument(
        "--system",
        default="x86_64-linux",
        help="Nix system the flake's packages.<system> outputs are built under (default: x86_64-linux)",
    )
    args = parser.parse_args()

    root = repo_root()
    if root is None:
        ci_log("Not in a git repo — treating as changed.")
        print("true")
        return

    if commit_exists(args.base, root):
        base = evaluate_at(args.base, args.system, root)
        if base is None:
            ci_log(f"Could not evaluate the base commit ('{args.base}').")
    else:
        ci_log(f"No usable base commit ('{args.base}').")
        base = None

    head = evaluate_at(args.head, args.system, root)

    if base is None or head is None:
        ci_log("Missing a comparable eval at one end of the range — treating as changed.")
        print("true")
        return

    changed = [pkg for pkg in PACKAGES if base[pkg] != head[pkg]]
    if changed:
        ci_log(f"changed: {', '.join(changed)}")
        print("true")
    else:
        ci_log("no relevant package drvPath changed")
        print("false")


if __name__ == "__main__":
    main()
