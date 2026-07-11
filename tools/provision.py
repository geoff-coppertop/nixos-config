#!/usr/bin/env python3
"""
provision.py

Enroll a NixOS machine: generate its age identity, add it to secrets.nix,
generate an SSH host keypair, create hosts/<name>/secrets.nix, and rekey.

Run this on an existing Linux machine before running `nix run .#install`.

Machine type (disko / sd-card / wsl) is declared in hosts/<name>/provision-type
and shown in the selection menu for clarity, but all types follow the same
enrollment path.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from common import die, repo_root
from enroll import enroll_machine

VALID_PROVISION_TYPES = {"disko", "sd-card", "wsl"}


def _discover_hosts(hosts_dir: Path) -> list[tuple[str, str]]:
    results = []
    for p in sorted(hosts_dir.iterdir()):
        if not p.is_dir():
            continue
        type_file = p / "provision-type"
        if not type_file.exists():
            print(f"  warning: {p.name} has no provision-type file — skipping", file=sys.stderr)
            continue
        mtype = type_file.read_text().strip()
        if mtype not in VALID_PROVISION_TYPES:
            die(f"{p.name}/provision-type contains unknown type '{mtype}' "
                f"(expected one of: {', '.join(sorted(VALID_PROVISION_TYPES))})")
        results.append((p.name, mtype))
    if not results:
        die(f"No provisionable hosts found under {hosts_dir}")
    return results


def _select_machine(hosts: list[tuple[str, str]]) -> tuple[str, str]:
    labels = {"disko": "[disko]", "sd-card": "[sd-card]", "wsl": "[wsl]"}
    print("Available machines:")
    print()
    for idx, (host, mtype) in enumerate(hosts, 1):
        print(f"  {idx}) {host:<20} {labels[mtype]}")
    print()

    # Only default when there's exactly one choice — no ambiguity to
    # accidentally default past on a real multi-host fleet.
    default = "1" if len(hosts) == 1 else None
    suffix = f" [{default}]" if default else ""
    while True:
        raw = input(f"Select machine [1-{len(hosts)}]{suffix}: ").strip()
        if not raw and default:
            raw = default
        if raw.isdigit():
            choice = int(raw)
            if 1 <= choice <= len(hosts):
                return hosts[choice - 1]
        print(f"Invalid selection — enter a number between 1 and {len(hosts)}.")


def main() -> None:
    print("=== NixOS Provision: Enroll Machine ===")
    print()

    root = repo_root()
    if root is None:
        die("Must be run from inside the nixos-config repo.")

    hosts = _discover_hosts(root / "hosts")
    machine, mtype = _select_machine(hosts)

    print()
    print(f"Machine : {machine}")
    print(f"Type    : {mtype}")
    print()

    identity_file = Path.home() / ".config" / "agenix" / f"{machine}.age"
    secrets_nix = root / "secrets" / "secrets.nix"

    already_enrolled = (
        identity_file.exists()
        and f'  {machine} = "age1' in secrets_nix.read_text()
    )

    if already_enrolled:
        print(f"{machine} is already enrolled (identity at {identity_file}).")
        print()
        print("To re-enroll, remove the entry from secrets/secrets.nix and delete")
        print(f"  {identity_file}")
    else:
        enroll_machine(machine)
        print()
        print(f"=== Enrollment complete: {machine} ===")

    print()
    print("Next: run  nix run .#install  to install the machine.")


if __name__ == "__main__":
    main()
