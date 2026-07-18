#!/usr/bin/env python3
"""
install.py

Install a NixOS machine. Runs enrollment automatically if not yet done.

  python3 tools/install.py   (or: nix run .#install)

Fetched and run standalone, e.g. from a live installer session with no
checkout present, it clones the full repo to /tmp/nixos-config and re-execs
itself from there so its sibling modules (common.py, enroll.py, ...) become
importable:

  nix-shell -p python3 git --run \\
    'python3 <(curl -fsSL https://raw.githubusercontent.com/geoff-coppertop/nixos-config/master/tools/install.py)'

Machine type is declared in hosts/<name>/provision-type:
  disko    — partition, format, and nixos-install; run from a NixOS live USB
  sd-card  — cross-compile SD image, flash, inject age identity

'wsl' is recognized (so an unrelated typo still gets caught) but not yet
wired up to a flow in this script — a fresh bootstrap-from-scratch via
WSL was never validated, and that usage is expected to wind down, so it's
deferred indefinitely rather than carried forward here.
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
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
SUPPORTED_TYPES = {"disko", "sd-card"}


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
    labels = {"disko": "[disko]", "sd-card": "[sd-card]"}
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


def _require_cmds_sdcard() -> None:
    for cmd in ("nix", "git", "lsblk", "dd", "zstd", "partprobe", "udisksctl", "udevadm"):
        if not shutil.which(cmd):
            _die(f"'{cmd}' not found. Run via: nix run .#install")


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


def _reread_partition_table(target_dev: str) -> None:
    """Force the kernel to notice target_dev's newly-written partition table.

    partprobe fails with "unable to inform the kernel" if anything is still
    mounted from the *old* partition table — e.g. the desktop's automounter
    grabbing a previous image's filesystems the instant a reused SD card or
    USB drive reappears, before the kernel has re-read what dd just wrote.
    dd already overwrote the disk itself, so there's nothing on those stale
    mounts worth preserving; unmount them first, then retry a few times
    before giving up, since the automounter can re-grab it in the same race
    window.
    """
    for _attempt in range(5):
        result = subprocess.run(
            ["lsblk", "-ln", "-o", "PATH,MOUNTPOINT", target_dev],
            capture_output=True, text=True, check=True,
        )
        for line in result.stdout.splitlines():
            parts = line.split(maxsplit=1)
            if len(parts) == 2 and parts[1]:
                run_sudo(["umount", parts[0]], check=False)

        if run_sudo(["partprobe", target_dev], check=False).returncode == 0:
            # partprobe succeeding only means the kernel accepted the new
            # partition table — it doesn't mean udev has finished re-probing
            # each partition's filesystem signature yet. Without this, lsblk
            # can still report a partition's old (or no) FSTYPE, and mount
            # can fail with "wrong fs type, bad option, bad superblock" even
            # though the correct filesystem is genuinely there. A fixed
            # sleep is the wrong tool for this — udevadm settle actually
            # waits for the real event queue to drain instead of guessing.
            run_sudo(["udevadm", "settle"], check=False)
            return
        time.sleep(2)

    _die(
        f"Could not get the kernel to re-read {target_dev}'s partition table "
        "after several attempts (something keeps remounting it). Unplug and "
        "replug the device, then re-run this tool."
    )


def _eject_device(target_dev: str) -> None:
    """Unmount and power off target_dev so it's safe to physically remove.

    The desktop's automounter (gvfs/udisks) reliably grabs newly-flashed
    partitions the moment the kernel picks up the new table — the same race
    _reread_partition_table() already works around for partprobe — which is
    why the Files app often shows nothing to eject even right after this
    flow finishes. udisksctl is the user-level (no sudo) mechanism GNOME's
    own eject button uses; power-off additionally cuts power to the USB
    port, so there's no ambiguity about whether it's actually safe to pull.
    """
    result = subprocess.run(
        ["lsblk", "-ln", "-o", "PATH,MOUNTPOINT", target_dev],
        capture_output=True, text=True, check=True,
    )
    for line in result.stdout.splitlines():
        parts = line.split(maxsplit=1)
        if len(parts) == 2 and parts[1]:
            run(["udisksctl", "unmount", "-b", parts[0]], check=False)

    if run(["udisksctl", "power-off", "-b", target_dev], check=False).returncode == 0:
        print(f"{target_dev} powered off — safe to remove.")
    else:
        print(f"Could not power off {target_dev} automatically; confirm nothing is mounted before removing it.")


def _lan_ip_placeholder(machine: str, repo: Path) -> bool:
    """True if hosts/<machine>/configuration.nix still has the placeholder
    lanIp (or has no lanIp convention at all) — i.e. Phase 1 hasn't set a
    real address yet.

    Defaults to True (assume first-time setup) when the file is missing or
    doesn't use this convention: the first-time instructions are harmless
    noise for an already-provisioned machine, but missing them would
    actually matter for a real first-timer.
    """
    config_file = repo / "hosts" / machine / "configuration.nix"
    if not config_file.exists():
        return True
    return "192.168.1.X" in config_file.read_text()


def _ssh_host_key_pinned(machine: str, repo: Path) -> bool:
    """True if lib/ssh-hosts.nix has a real (non-null) publicKey for
    machine — i.e. Phase 1's host-key collection step has actually run.

    Defaults to False (assume not yet pinned, so the caller falls back to
    the full first-time instructions) when the file is missing or the
    machine has no entry at all, for the same reason
    _lan_ip_placeholder() defaults the other way: better to show
    unnecessary instructions to someone re-flashing than to hide a real
    step from a genuine first-timer.
    """
    ssh_hosts_file = repo / "lib" / "ssh-hosts.nix"
    if not ssh_hosts_file.exists():
        return False
    match = re.search(
        rf"\b{re.escape(machine)}\s*=\s*{{(.*?)\n  }};",
        ssh_hosts_file.read_text(),
        re.DOTALL,
    )
    if not match:
        return False
    return "publicKey = null;" not in match.group(1)


def _already_provisioned(machine: str, repo: Path) -> bool:
    """True only if every repo-checkable Phase 1 step looks done: lanIp set
    to a real address AND the SSH host key actually pinned. The DHCP
    reservation itself lives in Unifi, outside this repo, so it can't be
    checked here — a real lanIp is the closest available proxy for it,
    since Phase 1 has you set lanIp to that same reserved address.
    """
    return not _lan_ip_placeholder(machine, repo) and _ssh_host_key_pinned(machine, repo)


def _sdcard_flow(machine: str, repo: Path) -> None:
    _require_cmds_sdcard()

    identity_file = Path.home() / ".config" / "agenix" / f"{machine}.age"

    print(f"--- Building SD image for {machine} ---")
    print("Cross-compilation for aarch64 — this may take a while.")
    print()

    image_link = repo / "result-sd-image"
    run([
        "nix", "build",
        f"{repo}#nixosConfigurations.{machine}.config.system.build.sdImage",
        "--out-link", str(image_link),
    ])

    img_zst = None
    sd_image_dir = image_link / "sd-image"
    for p in sd_image_dir.iterdir():
        if p.name.endswith(".img.zst"):
            img_zst = p
            break

    if img_zst is None:
        _die(f"No .img.zst found under {sd_image_dir}")

    img_file = Path(f"/tmp/{machine}.img")
    print()
    print(f"Decompressing to {img_file} ...")
    run(["zstd", "-d", str(img_zst), "-o", str(img_file), "--force"])
    print()

    print("--- Target device ---")
    print()
    run(["lsblk", "-d", "-o", "NAME,SIZE,MODEL,TRAN"])
    print()

    detected_dev = find_removable_disk()

    while True:
        if detected_dev:
            raw = input(f"Target device [{detected_dev}]: ").strip()
            target_dev = raw if raw else detected_dev
        else:
            target_dev = input("Target device: ").strip()

        if not target_dev:
            print("Device required.")
            continue
        if Path(target_dev).is_block_device():
            break
        print(f"'{target_dev}' is not a block device.")

    print()
    confirm_device(target_dev)
    print()

    print(f"--- Flashing to {target_dev} ---")
    run_sudo([
        "dd",
        f"if={img_file}",
        f"of={target_dev}",
        "bs=4M",
        "status=progress",
        "conv=fsync",
    ])

    # dd can run for several minutes; every step below also needs sudo, and
    # a real elapsed-time sudo session can expire during dd. Rather than
    # engineer around that, wrap the rest and fail with clear recovery
    # instructions instead of a raw traceback — dd's conv=fsync already
    # guarantees the image itself is safely on disk by this point, so a
    # failure here never means re-flashing.
    try:
        run_sudo(["sync"])
        print("Flash complete.")
        print()

        img_file.unlink(missing_ok=True)

        print("--- Installing age identity ---")
        print()

        # _reread_partition_table() already waits for udev to settle (not
        # just a fixed sleep), so lsblk below sees each partition's real,
        # freshly re-probed filesystem type.
        _reread_partition_table(target_dev)

        result = subprocess.run(
            ["lsblk", "-ln", "-o", "PATH,FSTYPE", target_dev],
            capture_output=True, text=True, check=True,
        )
        root_part = None
        for line in result.stdout.splitlines():
            parts = line.split()
            if len(parts) >= 2 and parts[1] == "ext4":
                root_part = parts[0]
                break

        if root_part is None:
            _die(f"Could not find an ext4 partition on {target_dev} after flashing.")

        print(f"Root partition: {root_part}")

        mnt_dir = Path(tempfile.mkdtemp())
        try:
            run_sudo(["mount", root_part, str(mnt_dir)])
            try:
                # mnt_dir was mounted via sudo (root-owned ext4 filesystem), so
                # this must run elevated too — a direct, non-elevated Python
                # function call would fail to create var/lib/agenix/ underneath
                # it. Match _disko_flow's pattern: invoke as a separate,
                # sudo-elevated subprocess rather than an in-process function
                # call.
                target_identity = mnt_dir / "var" / "lib" / "agenix" / "identity"
                run_sudo([
                    "python3",
                    str(repo / "tools" / "install_age_identity.py"),
                    "--file", str(identity_file),
                    "--target", str(target_identity),
                ])
            finally:
                run_sudo(["umount", str(mnt_dir)])
        finally:
            try:
                mnt_dir.rmdir()
            except OSError:
                pass
    except subprocess.CalledProcessError as e:
        print()
        print(f"A post-flash step failed: {' '.join(e.cmd)}")
        print(
            f"{target_dev} was already fully written (dd's conv=fsync guarantees "
            "that), so there is no need to reflash — this can be finished by hand:"
        )
        print()
        print("  sudo -v")
        print(f"  lsblk -o NAME,FSTYPE {target_dev}   # find the ext4 partition, if not already shown above")
        print(f"  sudo mkdir -p /mnt/{machine}-root")
        print(f"  sudo mount <ext4-partition> /mnt/{machine}-root")
        print(
            f"  sudo python3 {repo / 'tools' / 'install_age_identity.py'} "
            f"--file {identity_file} --target /mnt/{machine}-root/var/lib/agenix/identity"
        )
        print(f"  sudo umount /mnt/{machine}-root && sudo rmdir /mnt/{machine}-root")
        sys.exit(1)

    _eject_device(target_dev)

    print()
    print(f"=== Flash complete: {machine} ===")
    print()

    if not _already_provisioned(machine, repo):
        print("Next steps:")
        print()
        print(f"  1. Insert the card into {machine}, connect ethernet, power on")
        print("  2. Find the IP in the Unifi console (Clients list)")
        print("  3. Collect and pin the SSH host key:")
        print("       ssh-keyscan -t ed25519 <ip>")
        print('       # Add to lib/ssh-hosts.nix:  publicKey = "..."')
        print("  4. Set the DHCP reservation and LAN DNS server in the Unifi console")
        print(f"  5. Update hosts/{machine}/configuration.nix with the reserved IP")
        print("  6. Commit and deploy:")
        print(f"       git add -p && git commit -m 'fix: set {machine} reserved IP'")
        print(f"       nixos-rebuild switch --flake .#{machine} \\")
        print(f"         --target-host thomasga@{machine} --use-remote-sudo")
    else:
        print(
            f"{machine}'s lanIp is set to a real address and its SSH host "
            "key is already pinned in lib/ssh-hosts.nix — this looks like a "
            "re-flash of an already-provisioned machine, not a first-time setup."
        )
        print()
        print(
            f"Insert the card into {machine}, connect ethernet, power on — it "
            "should rejoin the network on its existing reserved IP with none of "
            "the first-time Unifi/SSH-host-key/lanIp steps needed again."
        )


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
    if mtype == "disko":
        _disko_flow(machine, active_repo, in_repo)
    elif mtype == "sd-card":
        _sdcard_flow(machine, active_repo)


if __name__ == "__main__":
    main()
