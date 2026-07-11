#!/usr/bin/env python3
"""Shared utilities for NixOS provisioning scripts."""

import getpass
import os
import subprocess
import sys
from pathlib import Path

SYSTEM_IDENTITY_PATH = Path("/var/lib/agenix/identity")


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


def run_sudo(cmd: list, extra_env: dict | None = None, **kwargs) -> subprocess.CompletedProcess:
    """Same as run() but prepends sudo.

    sudo resets the environment for the command it execs by default (unless
    the caller's sudoers has env_keep/--preserve-env for that variable), so
    passing env=... to subprocess.run only sets sudo's own environment — it
    does not reach the command afterward. extra_env values are instead
    passed as explicit VAR=value assignments on sudo's command line, which
    sudo always honors regardless of env_reset policy.
    """
    sudo_cmd = ["sudo"]
    if extra_env:
        sudo_cmd += [f"{key}={value}" for key, value in extra_env.items()]
    return run(sudo_cmd + cmd, **kwargs)


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


def system_identity_path() -> Path | None:
    """Return the deployed host's own age identity if present on disk."""
    return SYSTEM_IDENTITY_PATH if SYSTEM_IDENTITY_PATH.exists() else None


def agenix_command(identity_files: list[Path], args: list[str]) -> list[str]:
    """Build an argv for agenix, adding sudo only if reading any identity requires it.

    /var/lib/agenix/identity is root-owned on a deployed host, so it can't be
    read by the normal user account that runs secret-edit/secret-rekey. Rather
    than copy the host's private key into the user's home directory, elevate
    the single command that needs it.
    """
    needs_sudo = any(not os.access(f, os.R_OK) for f in identity_files)
    identity_opts = []
    for f in identity_files:
        identity_opts.extend(["-i", str(f)])
    cmd = ["agenix", *args, *identity_opts]
    if needs_sudo:
        cmd = ["sudo", "--preserve-env=EDITOR,RULES", *cmd]
    return cmd
