#!/usr/bin/env python3
"""
secret_rekey.py

Rekey agenix secrets with the recipients currently declared in
secrets/secrets.nix.

Each secret is rekeyed independently. agenix's own `--rekey` aborts the
entire batch the moment it hits one secret the running identities can't
decrypt (e.g. another host's own SSH key, scoped to that host + the offline
admin key), which silently leaves every alphabetically-later secret
un-rekeyed regardless of whether *those* could have been rekeyed. Doing them
one at a time means an undecryptable secret only skips itself, and the
summary at the end says exactly which were rekeyed and which were not.

Usage: python3 tools/secret_rekey.py
"""

import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from common import agenix_command, agenix_identity_files, repo_root, system_identity_path

ENTRY_RE = re.compile(r'^\s*"([^"]+)"\.publicKeys\s*=\s*\[.*?\];\s*$')


def _error_reason(stderr: str) -> str:
    """Pick the meaningful failure line out of agenix/age stderr.

    age prints a generic "report unexpected or unhelpful errors at
    filippo.io/age/report" footer *after* the real message, so the last line
    is usually noise. Prefer the line that actually names the error (contains
    'error:', which the footer's 'errors at' does not).
    """
    lines = [line.strip() for line in stderr.splitlines() if line.strip()]
    for line in lines:
        if "error:" in line.lower():
            return line
    return lines[-1] if lines else "unknown error"


def _find_enterprise_d_key() -> list[Path]:
    """Also check for the bare 'enterprise-d' key file (no extension)."""
    agenix_dir = Path.home() / ".config" / "agenix"
    if not agenix_dir.is_dir():
        return []
    candidate = agenix_dir / "enterprise-d"
    return [candidate] if candidate.exists() else []


def _identity_files() -> list[Path]:
    identity_files = list(agenix_identity_files())
    for key_file in _find_enterprise_d_key():
        if key_file not in identity_files:
            identity_files.append(key_file)
    system_identity = system_identity_path()
    if system_identity is not None and system_identity not in identity_files:
        identity_files.append(system_identity)
    return identity_files


def _parse_rules(rules_content: str) -> tuple[str, list[tuple[str, str]]]:
    """Split secrets.nix into its `let ... in {` header and the body's list
    of (secret name, full entry line) pairs.

    The header ends at the opening `in {` so a single entry can be appended
    to it to form a valid one-secret RULES file that still resolves the
    pubkey variables (enterprise-d, offlineAdmin, ...) defined in the let block.
    """
    marker = "in {"
    idx = rules_content.index(marker)
    header = rules_content[: idx + len(marker)]
    entries = []
    for line in rules_content[idx + len(marker):].splitlines():
        m = ENTRY_RE.match(line)
        if m:
            entries.append((m.group(1), line))
    return header, entries


def _rekey_one(
    header: str, entry_line: str, identity_files: list[Path], cwd: str
) -> subprocess.CompletedProcess:
    """Rekey a single secret via a temporary one-entry RULES file.

    The temp RULES lives in cwd and its entry keeps the original relative
    .age path, so agenix resolves the secret's storage location exactly as
    it would from the real secrets.nix.
    """
    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".nix", dir=cwd, delete=False
    ) as tmp:
        tmp.write(f"{header}\n{entry_line}\n}}\n")
        tmp_path = tmp.name
    try:
        env = {**os.environ, "RULES": tmp_path}
        cmd = agenix_command(identity_files, ["--rekey"])
        return subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True)
    finally:
        os.unlink(tmp_path)


def main() -> None:
    root = repo_root() or Path.cwd()
    rules = root / "secrets" / "secrets.nix"
    rules_content = rules.read_text()

    cwd = str(root) if '"secrets/' in rules_content else str(root / "secrets")
    identity_files = _identity_files()
    header, entries = _parse_rules(rules_content)

    if not entries:
        print("No secrets found in secrets.nix — nothing to rekey.")
        return

    rekeyed: list[str] = []
    skipped: list[tuple[str, str]] = []
    for name, line in entries:
        result = _rekey_one(header, line, identity_files, cwd)
        if result.returncode == 0:
            rekeyed.append(name)
            print(f"  rekeyed {name}")
        else:
            skipped.append((name, _error_reason(result.stderr)))
            print(f"  SKIPPED {name}")

    print()
    print(f"Rekeyed {len(rekeyed)}/{len(entries)} secrets.")
    if skipped:
        print()
        print("Not rekeyed — this machine's identities could not decrypt:")
        for name, reason in skipped:
            print(f"  {name}  —  {reason}")
        print()
        print(
            "That is correct ONLY for a secret deliberately scoped to another\n"
            "machine (that host's own SSH key). To rekey those, run this on a\n"
            "machine holding a matching identity, or place the offline admin key\n"
            "at ~/.config/agenix/ first. Any OTHER secret listed above is a real\n"
            "problem: every secret this machine is a recipient of should rekey."
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
