#!/usr/bin/env python3
"""
ci_changed_hosts.py

Decide which hosts CI actually has to build, by diffing the derivation itself
rather than guessing from changed file paths.

For each host, evaluate nixosConfigurations.<host>...toplevel.drvPath at the
base commit and again at the head commit of the push or PR. If the two store
paths are identical, the build is provably a no-op and the host is dropped
from the matrix. This needs no hand-maintained path-to-host map (which would
silently go stale), and it empties the matrix entirely for a docs-only change,
where no host's drvPath moves.

Fails safe everywhere: if the base commit is unusable (new branch, force-push,
shallow history) or an eval errors out, the affected host is built anyway.

Prints the build matrix — a JSON list of {"host", "runner"} objects — as a
single line on stdout, for the workflow to capture into $GITHUB_OUTPUT.
Per-host reasoning goes to stderr so the Actions log stays readable without
polluting that JSON.

Usage:
    python3 tools/ci_changed_hosts.py --base <sha> --head <sha>
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from common import repo_root

HOSTS = ["enterprise-d", "holodeck-01", "defiant", "excelsior"]

# defiant is aarch64-linux and builds natively on GitHub's arm64-hosted
# runners; every other host is x86_64-linux.
AARCH64_RUNNER = "ubuntu-24.04-arm"
X86_64_RUNNER = "ubuntu-latest"
RUNNERS = {host: AARCH64_RUNNER if host == "defiant" else X86_64_RUNNER for host in HOSTS}

NULL_SHA = "0" * 40


def log(msg: str) -> None:
    """Write a progress line to stderr, keeping stdout pure JSON."""
    print(msg, file=sys.stderr)


def commit_exists(sha: str, root: Path) -> bool:
    """True if sha names a commit object in this clone."""
    if not sha or sha == NULL_SHA:
        return False
    result = subprocess.run(
        ["git", "cat-file", "-e", f"{sha}^{{commit}}"],
        capture_output=True,
        cwd=str(root),
    )
    return result.returncode == 0


def checkout(sha: str, root: Path) -> bool:
    """Detach the working tree at sha. True on success."""
    result = subprocess.run(
        ["git", "checkout", "--quiet", "--detach", sha],
        capture_output=True,
        text=True,
        cwd=str(root),
    )
    if result.returncode != 0:
        log(f"git checkout {sha} failed: {result.stderr.strip()}")
        return False
    return True


def drv_path(host: str, root: Path) -> str | None:
    """Evaluate a host's toplevel drvPath at the current checkout.

    Returns None if the eval fails or produces nothing — the caller treats
    that as "changed" rather than risking a skipped build.
    """
    result = subprocess.run(
        [
            "nix",
            "eval",
            "--raw",
            f".#nixosConfigurations.{host}.config.system.build.toplevel.drvPath",
        ],
        capture_output=True,
        text=True,
        cwd=str(root),
    )
    if result.returncode != 0:
        return None
    return result.stdout.strip() or None


def eval_all(sha: str, root: Path) -> dict[str, str | None]:
    """Check out sha and evaluate every host's drvPath there."""
    if not checkout(sha, root):
        return {host: None for host in HOSTS}
    return {host: drv_path(host, root) for host in HOSTS}


def changed_hosts(base: str, head: str, root: Path) -> list[str]:
    """Hosts whose toplevel derivation differs between base and head."""
    if not commit_exists(base, root):
        log(f"No usable base commit ('{base}') — building every host.")
        return list(HOSTS)

    base_paths = eval_all(base, root)
    head_paths = eval_all(head, root)

    changed = []
    for host in HOSTS:
        if base_paths[host] is None or head_paths[host] is None:
            log(f"{host}: eval unavailable at one end of the range — building.")
            changed.append(host)
        elif base_paths[host] == head_paths[host]:
            log(f"{host}: drvPath unchanged — skipping build.")
        else:
            log(f"{host}: drvPath changed — building.")
            changed.append(host)
    return changed


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default="", help="base commit SHA of the push or PR")
    parser.add_argument("--head", required=True, help="head commit SHA of the push or PR")
    args = parser.parse_args()

    root = repo_root()
    if root is None:
        log("Not in a git repo — building every host.")
        hosts = list(HOSTS)
    else:
        hosts = changed_hosts(args.base, args.head, root)

    matrix = [{"host": host, "runner": RUNNERS[host]} for host in hosts]
    print(json.dumps(matrix, separators=(",", ":")))


if __name__ == "__main__":
    main()
