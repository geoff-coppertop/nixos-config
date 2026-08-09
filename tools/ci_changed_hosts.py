#!/usr/bin/env python3
"""
ci_changed_hosts.py

Decide which hosts CI actually has to build, by diffing the derivation itself
rather than guessing from changed file paths.

The host list is not written down here. It is read out of the flake at each
commit (`nixosConfigurations`), so registering a host in flake.nix is the only
step needed for it to get CI coverage — there is no second list to remember.
The runner is chosen the same way, from each host's own `pkgs.system`, so an
aarch64 host lands on an arm64 runner because of what it *is*, not because of
what it is *called*.

For each host defined at the head commit, evaluate its system and its
toplevel drvPath, and compare that drvPath against the same host's drvPath at
the base commit. If the two store paths are identical, the build is provably a
no-op and the host is dropped from the matrix. This needs no hand-maintained
path-to-host map (which would silently go stale), and it empties the matrix
entirely for a docs-only change, where no host's drvPath moves. A host that
exists at head but not at base — a newly added machine — has nothing to
compare against and is always built.

One `nix eval` per commit enumerates the host names; one more per host returns
that host's system and drvPath together, so adding the platform lookup costs no
extra evaluation. Keeping the per-host evals separate (rather than evaluating
the whole `nixosConfigurations` attrset in one shot) keeps a single broken host
from hiding every other host's result.

Fails safe everywhere: if the base commit is unusable (new branch, force-push,
shallow history) or an eval errors out, the affected host is built anyway. The
one hard failure is being unable to enumerate hosts at the head commit — there
is no safe list to fall back to, so the script exits non-zero and CI goes red
rather than silently building nothing.

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

# Nix systems to the GitHub-hosted runner that builds them natively. A host
# whose system is missing from this table (or could not be evaluated) still
# gets a job on the fallback runner: better a loud build failure than a host
# silently dropped from the matrix.
RUNNERS = {
    "x86_64-linux": "ubuntu-latest",
    "aarch64-linux": "ubuntu-24.04-arm",
}
FALLBACK_RUNNER = "ubuntu-latest"

# Applied to a single nixosConfiguration, returning its platform and its
# toplevel derivation in one evaluation. A drvPath carries store context;
# unsafeDiscardStringContext reduces it to a plain string so --json always
# serialises it as one, which is all this script compares.
#
# cfg.pkgs.system, not cfg.config.nixpkgs.hostPlatform.system: this repo's
# mkNixosSystem (lib/nixos-system.nix) calls nixpkgs.lib.nixosSystem with the
# top-level `system` argument, which selects the pkgs evaluation platform but
# does not populate the nixpkgs.hostPlatform *option* — that path evaluated
# to an error for every host, caught by nix_eval_json's blanket try/except,
# silently sending every host down the FALLBACK_RUNNER path (confirmed live:
# defiant landed on ubuntu-latest and failed with "a 'aarch64-linux' ... is
# required, but I am a 'x86_64-linux'"). cfg.pkgs.system is set unconditionally
# by nixpkgs on every pkgs instance regardless of how system was threaded in,
# so it doesn't depend on that option wiring.
HOST_INFO_EXPR = """
  cfg: {
    system = cfg.pkgs.system;
    drvPath = builtins.unsafeDiscardStringContext cfg.config.system.build.toplevel.drvPath;
  }
"""

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


def nix_eval_json(attr: str, apply: str, root: Path):
    """Run `nix eval --json <attr> --apply <apply>`. None if it fails.

    Logs the actual nix stderr on failure — silently returning None here
    once already cost real time to diagnose (a broken attribute path in
    HOST_INFO_EXPR failed every host's eval without a visible reason).
    """
    result = subprocess.run(
        ["nix", "eval", "--json", attr, "--apply", apply],
        capture_output=True,
        text=True,
        cwd=str(root),
    )
    if result.returncode != 0:
        log(f"nix eval {attr} failed: {result.stderr.strip()}")
        return None
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        log(f"nix eval {attr} produced non-JSON output: {result.stdout.strip()!r}")
        return None


def host_names(root: Path) -> list[str] | None:
    """Every host registered in the flake's nixosConfigurations, or None."""
    names = nix_eval_json(".#nixosConfigurations", "builtins.attrNames", root)
    if not isinstance(names, list):
        return None
    return sorted(names)


def host_info(host: str, root: Path) -> dict[str, str] | None:
    """A host's system and toplevel drvPath at the current checkout.

    Returns None if the eval fails or produces nothing — the caller treats
    that as "changed" rather than risking a skipped build.
    """
    info = nix_eval_json(f".#nixosConfigurations.{host}", HOST_INFO_EXPR, root)
    if not isinstance(info, dict) or not info.get("drvPath"):
        return None
    return info


def evaluate(root: Path) -> dict[str, dict[str, str] | None] | None:
    """Evaluate every host defined at the current checkout, or None."""
    names = host_names(root)
    if names is None:
        return None
    return {name: host_info(name, root) for name in names}


def evaluate_at(sha: str, root: Path) -> dict[str, dict[str, str] | None] | None:
    """Check out sha and evaluate every host defined there."""
    if not checkout(sha, root):
        return None
    return evaluate(root)


def changed_hosts(base: dict | None, head: dict) -> list[str]:
    """Hosts whose toplevel derivation differs between base and head."""
    if base is None:
        log("No usable base commit — building every host.")
        return list(head)

    changed = []
    for host, head_info in head.items():
        base_info = base.get(host)
        if head_info is None or base_info is None:
            log(f"{host}: no comparable eval at both ends of the range — building.")
            changed.append(host)
        elif base_info["drvPath"] == head_info["drvPath"]:
            log(f"{host}: drvPath unchanged — skipping build.")
        else:
            log(f"{host}: drvPath changed — building.")
            changed.append(host)
    return changed


def runner_for(host: str, info: dict[str, str] | None) -> str:
    """The runner that builds this host natively, from its own system."""
    system = info.get("system") if info else None
    if not system:
        log(f"{host}: system unknown — assigning {FALLBACK_RUNNER}.")
        return FALLBACK_RUNNER
    runner = RUNNERS.get(system)
    if runner is None:
        log(f"{host}: no runner mapped for {system} — assigning {FALLBACK_RUNNER}.")
        return FALLBACK_RUNNER
    return runner


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default="", help="base commit SHA of the push or PR")
    parser.add_argument("--head", required=True, help="head commit SHA of the push or PR")
    args = parser.parse_args()

    root = repo_root()
    if root is None:
        log("Not in a git repo — evaluating the working tree and building every host.")
        head = evaluate(Path.cwd())
        base = None
    else:
        # Base first, so the working tree is left at head for later steps.
        if commit_exists(args.base, root):
            base = evaluate_at(args.base, root)
            if base is None:
                log(f"Could not evaluate the base commit ('{args.base}').")
        else:
            log(f"No usable base commit ('{args.base}').")
            base = None
        head = evaluate_at(args.head, root)

    if head is None:
        log("Could not enumerate nixosConfigurations at head — refusing to guess.")
        sys.exit(1)

    matrix = [
        {"host": host, "runner": runner_for(host, head[host])}
        for host in changed_hosts(base, head)
    ]
    print(json.dumps(matrix, separators=(",", ":")))


if __name__ == "__main__":
    main()
