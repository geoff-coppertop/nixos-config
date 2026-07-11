#!/usr/bin/env python3
"""
secret_rekey.py

Rekey agenix secrets with new host keys. Replicates the secretRekey bash logic
from lib/secret-apps.nix.

Usage: python3 tools/secret_rekey.py
"""

import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from common import agenix_command, agenix_identity_files, repo_root, system_identity_path


def _find_enterprise_d_key() -> list[Path]:
    """Also check for the bare 'enterprise-d' key file (no extension)."""
    agenix_dir = Path.home() / ".config" / "agenix"
    if not agenix_dir.is_dir():
        return []
    extra = []
    candidate = agenix_dir / "enterprise-d"
    if candidate.exists():
        extra.append(candidate)
    return extra


def main() -> None:
    root = repo_root() or Path.cwd()
    rules = root / "secrets" / "secrets.nix"
    os.environ["RULES"] = str(rules)

    rules_content = rules.read_text() if rules.exists() else ""
    if '"secrets/' in rules_content:
        cwd = str(root)
    else:
        cwd = str(root / "secrets")

    identity_files = list(agenix_identity_files())
    for key_file in _find_enterprise_d_key():
        if key_file not in identity_files:
            identity_files.append(key_file)
    system_identity = system_identity_path()
    if system_identity is not None and system_identity not in identity_files:
        identity_files.append(system_identity)

    os.chdir(cwd)
    cmd = agenix_command(identity_files, ["--rekey"])
    os.execvp(cmd[0], cmd)


if __name__ == "__main__":
    main()
