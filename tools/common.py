#!/usr/bin/env python3
"""Shared utilities for NixOS provisioning scripts."""

import getpass
import subprocess
import sys
from pathlib import Path


def die(msg: str) -> None:
    """Print error message to stderr and exit with code 1."""
    print(f"Error: {msg}", file=sys.stderr)
    sys.exit(1)


def repo_root() -> Path | None:
    """Return the repo root Path from git, or None if not in a repo."""
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
    )
    if result.returncode == 0:
        return Path(result.stdout.strip())
    return None


def run(cmd: list, **kwargs) -> subprocess.CompletedProcess:
    """Thin wrapper around subprocess.run with check=True."""
    kwargs.setdefault("check", True)
    return subprocess.run(cmd, **kwargs)


def run_sudo(cmd: list, **kwargs) -> subprocess.CompletedProcess:
    """Same as run() but prepends sudo."""
    return run(["sudo"] + cmd, **kwargs)


def prompt(message: str, default: str | None = None) -> str:
    """Read a line from stdin with optional default. Exits if value is empty."""
    if default is not None:
        raw = input(f"{message} [{default}]: ").strip()
        value = raw if raw else default
    else:
        value = input(f"{message}: ").strip()
    if not value:
        die("value required")
    return value


def prompt_secret(message: str) -> str:
    """Read a secret from stdin without echo, confirm match."""
    while True:
        value = getpass.getpass(f"{message}: ")
        if not value:
            continue
        confirm = getpass.getpass("Confirm: ")
        if value == confirm:
            return value
        print("Passphrases do not match.")


def confirm_device(device: str) -> None:
    """Ask user to type the device path back to confirm destructive operation."""
    print(f"WARNING: ALL data on {device} will be overwritten.")
    confirm = input(f"Type the device name to confirm [{device}]: ").strip()
    if confirm != device:
        die(f"Confirmation did not match '{device}'. Aborting.")


def find_removable_disk() -> str | None:
    """Parse lsblk to find first removable disk. Returns /dev/NAME string or None."""
    result = subprocess.run(
        ["lsblk", "-d", "-o", "NAME,RM,TYPE", "--noheadings"],
        capture_output=True,
        text=True,
        check=True,
    )
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[1] == "1" and parts[2] == "disk":
            return f"/dev/{parts[0]}"
    return None


def agenix_identity_files() -> list[Path]:
    """Return list of Path objects from ~/.config/agenix/ matching *.age or *.key."""
    agenix_dir = Path.home() / ".config" / "agenix"
    if not agenix_dir.is_dir():
        return []
    files = []
    for pattern in ("*.age", "*.key"):
        files.extend(agenix_dir.glob(pattern))
    return files
