#!/usr/bin/env python3
"""
install.py

Install a NixOS machine via disko, from a NixOS live USB. Runs enrollment
automatically if not yet done.

  python3 tools/install.py   (or: nix run .#install)

Fetched and run standalone, e.g. from a live installer session with no
checkout present, it clones the full repo to /tmp/nixos-config and re-execs
itself from there so its sibling modules (common.py, enroll.py, ...) become
importable:

  nix-shell -p python3 git --run \\
    'python3 <(curl -fsSL https://raw.githubusercontent.com/geoff-coppertop/nixos-config/master/tools/install.py)'

Machine type is declared in hosts/<name>/provision-type. Only 'disko' is
currently supported here — 'sd-card' and 'wsl' are recognized (so an
unrelated typo still gets caught) but not yet wired up to a flow in this
script; hosts declaring those types are skipped until that support lands
in a follow-up, once there's an actual environment to validate them against.
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

DEFAULT_REPO_URL = "https://github.com/geoff-coppertop/nixos-config"
REPO_TMP = Path("/tmp/nixos-config")


def _self_bootstrap() -> None:
    """Clone the repo and re-exec from inside it.

    Runs only when install.py was fetched standalone (e.g. curl'd directly
    from a live installer session) and its sibling modules aren't sitting
    next to it on disk. Mirrors the old bash installer's curl-and-go UX
    without requiring a manual git clone step first.
    """
    repo_url = os.environ.get("NIXOS_CONFIG_REPO", DEFAULT_REPO_URL)
    repo_ref = os.environ.get("NIXOS_CONFIG_REF")
    print("install.py: running standalone — cloning the full repo first...")
    # Step out of REPO_TMP first: if the caller's cwd is already REPO_TMP
    # (e.g. a leftover manual clone from an earlier attempt), rm -rf would
    # delete our own working directory and the git clone below would fail
    # with "Unable to read current working directory".
    os.chdir("/")
    subprocess.run(["rm", "-rf", str(REPO_TMP)], check=False)
    clone_cmd = ["git", "clone"]
    if repo_ref:
        clone_cmd += ["-b", repo_ref]
    clone_cmd += [repo_url, str(REPO_TMP)]
    subprocess.run(clone_cmd, check=True)
    os.chdir(REPO_TMP)
    os.execvp("python3", ["python3", str(REPO_TMP / "tools" / "install.py")])


sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    from common import (
        confirm_device,
        die as _die,
        find_removable_disk,
        prompt,
        prompt_secret,
        repo_root,
        run,
        run_sudo,
    )
    from enroll import enroll_machine
except ImportError:
    _self_bootstrap()


NIX_CONFIG = "experimental-features = nix-command flakes"

VALID_PROVISION_TYPES = {"disko", "sd-card", "wsl"}
SUPPORTED_TYPES = {"disko"}


# ── discovery ─────────────────────────────────────────────────────────────────

def _discover_hosts(hosts_dir: Path) -> list[tuple[str, str]]:
    results = []
    for p in sorted(hosts_dir.iterdir()):
        if not p.is_dir():
            continue
        type_file = p / "provision-type"
        if not type_file.exists():
            continue
        mtype = type_file.read_text().strip()
        if mtype not in VALID_PROVISION_TYPES:
            _die(f"{p.name}/provision-type contains unknown type '{mtype}' "
                 f"(expected one of: {', '.join(sorted(VALID_PROVISION_TYPES))})")
        if mtype not in SUPPORTED_TYPES:
            print(f"  note: {p.name} ({mtype}) not yet supported by install.py — skipping",
                  file=sys.stderr)
            continue
        results.append((p.name, mtype))
    if not results:
        _die(f"No installable hosts found under {hosts_dir}")
    return results


def _select_machine(hosts: list[tuple[str, str]]) -> tuple[str, str]:
    labels = {"disko": "[disko]"}
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


# ── Linux flows ───────────────────────────────────────────────────────────────

def _require_cmds_disko() -> None:
    for cmd in ("git", "nix", "nixos-install", "shred"):
        if not shutil.which(cmd):
            _die(f"'{cmd}' not found — run from a NixOS live USB with networking.")


def _disko_flow(machine: str, active_repo: Path, in_repo: bool) -> None:
    _require_cmds_disko()

    repo_target = Path("/mnt/etc/nixos/nixos-config")
    key_filename = "nixos-config.age"

    run(["lsblk", "-d", "-o", "NAME,SIZE,MODEL,TRAN"])
    print()

    result = subprocess.run(
        ["lsblk", "-d", "-b", "-o", "NAME,TYPE,SIZE", "--noheadings"],
        capture_output=True, text=True, check=True,
    )
    # Floppy controllers (fd0) commonly report TYPE=disk with a near-zero
    # size, which would otherwise be suggested ahead of the real target disk.
    # 1 GiB is comfortably below any real install target and comfortably
    # above a phantom/legacy device's size.
    min_disk_bytes = 1024**3
    detected_disk = None
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[1] == "disk":
            try:
                size = int(parts[2])
            except ValueError:
                continue
            if size >= min_disk_bytes:
                detected_disk = f"/dev/{parts[0]}"
                break

    target_disk = prompt("Target disk device", detected_disk)
    if not Path(target_disk).is_block_device():
        _die(f"{target_disk} is not a block device.")

    luks_passphrase = prompt_secret("LUKS passphrase")

    print()
    print("Age identity key source:")
    print("  1) USB drive")
    print("  2) File path")
    print("  3) Skip")
    print()

    key_source_choice = input("Choice [1/2/3]: ").strip()
    key_device = ""
    key_file_path = ""

    if key_source_choice == "1":
        print()
        print(f"Insert the USB drive containing {key_filename} and press Enter.")
        input()
        detected_key_dev = find_removable_disk()
        if detected_key_dev:
            detected_key_dev = detected_key_dev + "1"
        key_device = prompt("Key USB partition", detected_key_dev)
    elif key_source_choice == "2":
        key_file_path = prompt(
            "Absolute path to the key file",
            f"/run/media/nixos/keys/{key_filename}",
        )
    elif key_source_choice == "3":
        print("Skipping age identity install.")
    else:
        _die("Invalid choice.")

    do_shred = False
    if key_source_choice != "3":
        shred_choice = input("Shred source key after copy? [y/N]: ").strip()
        do_shred = shred_choice.lower() == "y"

    print()
    print("=== Securing live session ===")
    run_sudo(["passwd", "-l", "nixos"])

    passphrase_file = Path("/tmp/encryption-password")
    passphrase_file.touch(mode=0o600)
    passphrase_file.write_text(luks_passphrase)
    del luks_passphrase

    try:
        # Only re-clone into REPO_TMP when active_repo is a different,
        # possibly-dirty working copy (e.g. a developer's own checkout).
        # When active_repo already IS REPO_TMP — always true after
        # _self_bootstrap, which clones straight into REPO_TMP — this would
        # otherwise rm -rf our own cwd and then try to clone that
        # now-deleted path into itself.
        if in_repo and active_repo.resolve() != REPO_TMP.resolve():
            print()
            print("=== Cloning repo ===")
            os.chdir("/")
            run_sudo(["rm", "-rf", str(REPO_TMP)])
            run_sudo(
                ["nix-shell", "-p", "git", "--run",
                 f"git clone '{active_repo}' '{REPO_TMP}'"],
                extra_env={"NIX_CONFIG": NIX_CONFIG},
            )
            active_repo = REPO_TMP
            os.chdir(REPO_TMP)

        print()
        print("=== Provisioning disks ===")
        run_sudo([
            "nix", "run", "github:nix-community/disko", "--",
            "--mode", "destroy,format,mount",
            "--arg", "disks", f'[ "{target_disk}" ]',
            str(active_repo / "hosts" / machine / "disko.nix"),
        ], extra_env={"NIX_CONFIG": NIX_CONFIG})

        print()
        print("=== Verifying mounts ===")
        run(["findmnt", "/mnt"])
        run(["findmnt", "/mnt/boot"])

        print()
        print("=== Copying repo ===")
        run_sudo(["mkdir", "-p", "-m", "0700", "/mnt/etc/nixos"])
        run_sudo(["cp", "-r", str(active_repo), str(repo_target)])
        run_sudo(["chown", "-R", "root:root", str(repo_target)])

        if key_source_choice != "3":
            print()
            print("=== Installing age identity ===")
            target_identity = Path("/mnt/var/lib/agenix/identity")
            if key_device:
                run_sudo([
                    "python3",
                    str(repo_target / "tools" / "install_age_identity.py"),
                    "--device", key_device,
                    "--target", str(target_identity),
                ] + (["--shred"] if do_shred else []))
            else:
                run_sudo([
                    "python3",
                    str(repo_target / "tools" / "install_age_identity.py"),
                    "--file", key_file_path,
                    "--target", str(target_identity),
                ] + (["--shred"] if do_shred else []))

        print()
        print("=== Initializing Secure Boot Keys ===")
        run_sudo(["mkdir", "-p", "-m", "0700", "/mnt/etc/secureboot"])
        run_sudo(["mkdir", "-p", "-m", "0700", "/var/lib/sbctl"])
        run_sudo(["mount", "--bind", "/mnt/etc/secureboot", "/var/lib/sbctl"])
        run_sudo(
            ["nix", "run", "nixpkgs#sbctl", "--", "create-keys"],
            extra_env={"NIX_CONFIG": NIX_CONFIG},
        )
        run_sudo(["umount", "/var/lib/sbctl"])

        print()
        print("=== Running nixos-install ===")
        run_sudo(
            ["nixos-install", "--flake", f"{active_repo}#{machine}"],
            extra_env={"NIX_CONFIG": NIX_CONFIG},
        )

        print()
        print("=== Install complete ===")
        print("Remove installation media and reboot.")

    finally:
        try:
            run_sudo(["shred", "-vfzu", str(passphrase_file)], check=False)
        except Exception:
            pass


# ── entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    os.environ["NIX_CONFIG"] = NIX_CONFIG

    print("=== NixOS Install ===")
    print()

    root = repo_root()
    in_repo = root is not None

    if not in_repo:
        print("Not inside a git repo — this looks like a live USB session.")
        print()
        repo_url = input(f"Git repo URL [{DEFAULT_REPO_URL}]: ").strip() or DEFAULT_REPO_URL
        print()
        print("=== Cloning repo ===")
        os.chdir("/")
        run_sudo(["rm", "-rf", str(REPO_TMP)])
        run_sudo(
            ["nix-shell", "-p", "git", "--run",
             f"git clone '{repo_url}' '{REPO_TMP}'"],
            extra_env={"NIX_CONFIG": NIX_CONFIG},
        )
        hosts_dir = REPO_TMP / "hosts"
    else:
        hosts_dir = root / "hosts"

    hosts = _discover_hosts(hosts_dir)
    machine, mtype = _select_machine(hosts)

    print()
    print(f"Machine : {machine}")
    print(f"Type    : {mtype}")
    print()

    # Enrollment status is a repo-level fact (is the machine's key already
    # declared in secrets.nix?), not a local one. A live installer session
    # has no reason to hold a copy of the machine's identity file in its
    # own ephemeral $HOME — that file was generated wherever enrollment
    # originally happened, which is typically a different machine
    # entirely. Requiring it here made install.py re-run full enrollment
    # (including a rekey with no usable identity) for every already
    # enrolled machine installed from a fresh live session.
    secrets_nix = (root if in_repo else REPO_TMP) / "secrets" / "secrets.nix"
    already_enrolled = f'  {machine} = "age1' in secrets_nix.read_text()
    if not already_enrolled:
        print(f"--- {machine} is not enrolled — running enrollment first ---")
        print()
        enroll_machine(machine)
        print()

    active_repo = root if in_repo else REPO_TMP
    _disko_flow(machine, active_repo, in_repo)


if __name__ == "__main__":
    main()
