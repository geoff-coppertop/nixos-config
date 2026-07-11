#!/usr/bin/env python3
"""
secret_edit.py

Edit an encrypted agenix secret. Replicates the secretEdit bash logic
from lib/secret-apps.nix.

Usage: python3 tools/secret_edit.py secrets/<name>.age
"""

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from common import agenix_command, agenix_identity_files, die, repo_root, system_identity_path


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: nix run .#secret-edit secrets/<name>.age", file=sys.stderr)
        sys.exit(1)

    full_path = sys.argv[-1]

    if not (full_path.startswith("secrets/") and full_path.endswith(".age")):
        die("Secret path must live under secrets/ and end with .age.")

    root = repo_root() or Path.cwd()

    # Ensure the directory exists
    Path(full_path).parent.mkdir(parents=True, exist_ok=True)

    rules = root / "secrets" / "secrets.nix"
    os.environ["RULES"] = str(rules)

    rules_content = rules.read_text() if rules.exists() else ""
    if '"secrets/' in rules_content:
        cwd = str(root)
        target_path = full_path
    else:
        cwd = str(root / "secrets")
        target_path = full_path.removeprefix("secrets/")

    identity_files = list(agenix_identity_files())
    system_identity = system_identity_path()
    if system_identity is not None and system_identity not in identity_files:
        identity_files.append(system_identity)

    os.chdir(cwd)
    cmd = agenix_command(identity_files, ["-e", target_path])
    os.execvp(cmd[0], cmd)


if __name__ == "__main__":
    main()
