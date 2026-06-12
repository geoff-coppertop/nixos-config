#!/usr/bin/env python3
"""
check_no_plaintext_secrets.py

Pre-commit hook: refuses to commit plaintext secrets.
Checks staged files for private key patterns and non-.age files under secrets/.
"""

import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from common import repo_root

PRIVATE_KEY_REGEX = re.compile(
    r"BEGIN (OPENSSH|RSA|EC|DSA|PGP) PRIVATE KEY|AGE-SECRET-KEY-"
)
SECRET_CONTENT_REGEX = re.compile(r"^(username|password)=", re.MULTILINE)


def main() -> None:
    root = repo_root()
    if root is None:
        # Not in a repo — nothing to check.
        sys.exit(0)

    result = subprocess.run(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR"],
        capture_output=True,
        text=True,
        check=True,
        cwd=str(root),
    )

    staged_files = [f for f in result.stdout.splitlines() if f]

    if not staged_files:
        sys.exit(0)

    bad_paths = []
    bad_contents = []

    for path in staged_files:
        if not path:
            continue

        # Non-.age files under secrets/ (except secrets/secrets.nix)
        if (
            path.startswith("secrets/")
            and path != "secrets/secrets.nix"
            and not path.endswith(".age")
        ):
            bad_paths.append(path)
            continue

        # Skip tools/
        if path.startswith("tools/"):
            continue

        # Check if the object exists in the index
        check = subprocess.run(
            ["git", "cat-file", "-e", f":{path}"],
            capture_output=True,
            cwd=str(root),
        )
        if check.returncode != 0:
            continue

        # Skip .age files for content checks
        if path.endswith(".age"):
            continue

        content_result = subprocess.run(
            ["git", "show", f":{path}"],
            capture_output=True,
            text=True,
            cwd=str(root),
        )
        staged_content = content_result.stdout

        if path.startswith("secrets/"):
            if SECRET_CONTENT_REGEX.search(staged_content) or PRIVATE_KEY_REGEX.search(staged_content):
                bad_contents.append(path)
                continue

        if PRIVATE_KEY_REGEX.search(staged_content):
            bad_contents.append(path)

    if bad_paths:
        print("Refusing to commit non-.age files under secrets/:", file=sys.stderr)
        for p in bad_paths:
            print(f"  {p}", file=sys.stderr)
        print(file=sys.stderr)
        print(
            "Create or rotate secrets with: nix run .#secret-edit -- secrets/<name>.age",
            file=sys.stderr,
        )
        sys.exit(1)

    if bad_contents:
        print("Refusing to commit likely plaintext secret material:", file=sys.stderr)
        for p in bad_contents:
            print(f"  {p}", file=sys.stderr)
        print(file=sys.stderr)
        print(
            "Do not stage plaintext credentials or private keys. "
            "Use agenix and commit only .age files.",
            file=sys.stderr,
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
