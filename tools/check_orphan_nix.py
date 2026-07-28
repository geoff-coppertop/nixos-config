#!/usr/bin/env python3
"""
check_orphan_nix.py

Pre-commit hook and flake check: refuses a .nix file that nothing imports.

A .nix file no default.nix (or host config) imports is silently inert — it is
never evaluated, so no error is ever raised. Nothing else in the toolchain
catches this: `nix flake check` never sees the file, `deadnix` finds unused
bindings rather than unimported files, and `statix`/`alejandra` are per-file.

The check walks import edges out from flake.nix and reports any tracked .nix
file it cannot reach.
"""

import re
import subprocess
import sys
from pathlib import Path


# Relative path literals: ./foo.nix, ../../profiles/common, ./home/alice.nix.
# Nix has no other way to reference a file in-tree, so a literal scan is
# sufficient here and avoids depending on a Nix evaluator.
PATH_REGEX = re.compile(r"\.{1,2}/[A-Za-z0-9._/-]+")

ROOT_FILE = "flake.nix"

# Directories whose .nix files are never imported by the flake.
EXCLUDED_PREFIXES = ("secrets/",)

# Build output and tooling directories, skipped by the non-git fallback walk.
IGNORED_DIRS = {".git", "result", ".direnv", "node_modules"}

# Files that are deliberately not imported. Add an entry only with a comment
# explaining why the file exists without being wired in.
ALLOWED_ORPHANS: set[str] = set()


def all_nix_files(root: Path) -> list[str]:
    """Every .nix file in the tree, from git when available.

    The flake check runs this inside a build sandbox where `src` was filtered
    by cleanSource, so there is no .git to query — fall back to walking the
    filesystem there. Returning an empty list in that case would make the
    check pass vacuously, which is worse than not having it.
    """
    result = subprocess.run(
        ["git", "ls-files", "*.nix"],
        capture_output=True,
        text=True,
        cwd=str(root),
    )
    if result.returncode == 0:
        found = result.stdout.splitlines()
    else:
        found = [
            str(p.relative_to(root))
            for p in root.rglob("*.nix")
            if not any(part in IGNORED_DIRS for part in p.parts)
        ]

    return [f for f in found if f and not f.startswith(EXCLUDED_PREFIXES)]


def resolve(root: Path, source: str, ref: str) -> str | None:
    """Resolve a path literal found in `source` to a repo-relative .nix file."""
    target = (root / source).parent / ref
    try:
        target = target.resolve()
        target.relative_to(root.resolve())
    except (OSError, ValueError):
        return None

    # A directory reference means its default.nix, the way Nix resolves it.
    if target.is_dir():
        target = target / "default.nix"
    if target.suffix != ".nix" or not target.is_file():
        return None

    return str(target.relative_to(root.resolve()))


def imports_from(root: Path, path: str) -> set[str]:
    try:
        text = (root / path).read_text()
    except OSError:
        return set()

    found = set()
    for ref in PATH_REGEX.findall(text):
        resolved = resolve(root, path, ref)
        if resolved is not None:
            found.add(resolved)
    return found


def reachable(root: Path) -> set[str]:
    """Every .nix file reachable by import edges out from flake.nix."""
    seen = {ROOT_FILE}
    queue = [ROOT_FILE]
    while queue:
        for nxt in imports_from(root, queue.pop()):
            if nxt not in seen:
                seen.add(nxt)
                queue.append(nxt)
    return seen


def main() -> None:
    # Always resolve from this file's own location (tools/ -> root), never from
    # the process cwd. The flake check copies the tree into a sandbox and runs
    # from there; resolving via `git rev-parse` would silently check whatever
    # repo the caller happened to be standing in instead.
    root = Path(__file__).resolve().parent.parent

    if not (root / ROOT_FILE).is_file():
        print(f"Cannot locate {ROOT_FILE} from {root}", file=sys.stderr)
        sys.exit(1)

    orphans = sorted(set(all_nix_files(root)) - reachable(root) - ALLOWED_ORPHANS)

    if orphans:
        print("Unimported .nix files — these are never evaluated:", file=sys.stderr)
        for path in orphans:
            print(f"  {path}", file=sys.stderr)
        print(file=sys.stderr)
        print(
            "Add each to its sibling default.nix, or to ALLOWED_ORPHANS in "
            "tools/check_orphan_nix.py with a comment saying why it is not "
            "wired in.",
            file=sys.stderr,
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
