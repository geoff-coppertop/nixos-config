#!/usr/bin/env python3
"""
install.py

Install a NixOS machine. Runs enrollment automatically if not yet done.

Platform-aware: runs disko and sd-card flows on Linux, WSL flow on Windows.

  Linux:   python3 tools/install.py   (or: nix run .#install)
  Windows: python  tools\\install.py

Machine type is declared in hosts/<name>/provision-type:
  disko    — partition, format, and nixos-install; run from a NixOS live USB
  sd-card  — cross-compile SD image, flash, inject age identity
  wsl      — WSL2 bootstrap (fetch NixOS-WSL, wsl --import, nixos-rebuild)
"""

import json
import os
import platform
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

IS_WINDOWS = platform.system() == "Windows"

if not IS_WINDOWS:
    sys.path.insert(0, str(Path(__file__).parent))
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
    from install_age_identity import install_age_identity
else:
    def _die(msg: str) -> None:
        print(f"Error: {msg}", file=sys.stderr)
        sys.exit(1)

    def repo_root() -> "Path | None":
        r = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True,
        )
        return Path(r.stdout.strip()) if r.returncode == 0 else None


NIX_CONFIG = "experimental-features = nix-command flakes"
DEFAULT_REPO_URL = "https://github.com/geoff-coppertop/nixos-config"
REPO_TMP = Path("/tmp/nixos-config")

NIXOS_WSL_RELEASES_URL = "https://api.github.com/repos/nix-community/NixOS-WSL/releases/latest"
WSL_DISTRO_NAME = "NixOS"
WSL_DEFAULT_DISK_SIZE_GB = 50

LINUX_TYPES = {"disko", "sd-card"}
WINDOWS_TYPES = {"wsl"}
VALID_PROVISION_TYPES = LINUX_TYPES | WINDOWS_TYPES


# ── discovery ─────────────────────────────────────────────────────────────────

def _discover_hosts(hosts_dir: Path) -> list[tuple[str, str]]:
    platform_types = WINDOWS_TYPES if IS_WINDOWS else LINUX_TYPES
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
        if mtype in platform_types:
            results.append((p.name, mtype))
    if not results:
        plat = "Windows" if IS_WINDOWS else "Linux"
        _die(f"No installable hosts for {plat} found under {hosts_dir}")
    return results


def _select_machine(hosts: list[tuple[str, str]]) -> tuple[str, str]:
    labels = {"disko": "[disko]", "sd-card": "[sd-card]", "wsl": "[wsl]"}
    print("Available machines:")
    print()
    for idx, (host, mtype) in enumerate(hosts, 1):
        print(f"  {idx}) {host:<20} {labels[mtype]}")
    print()
    while True:
        raw = input(f"Select machine [1-{len(hosts)}]: ").strip()
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
    for cmd in ("nix", "git", "lsblk", "dd", "zstd", "partprobe"):
        if not shutil.which(cmd):
            _die(f"'{cmd}' not found. Run via: nix develop -c python3 tools/install.py")


def _disko_flow(machine: str, active_repo: Path, in_repo: bool) -> None:
    _require_cmds_disko()

    repo_target = Path("/mnt/etc/nixos/nixos-config")
    key_filename = "nixos-config.age"

    run(["lsblk", "-d", "-o", "NAME,SIZE,MODEL,TRAN"])
    print()

    result = subprocess.run(
        ["lsblk", "-d", "-o", "NAME,TYPE", "--noheadings"],
        capture_output=True, text=True, check=True,
    )
    detected_disk = None
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[1] == "disk":
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
        if in_repo:
            print()
            print("=== Cloning repo ===")
            run_sudo(["rm", "-rf", str(REPO_TMP)])
            env = os.environ.copy()
            env["NIX_CONFIG"] = NIX_CONFIG
            run_sudo(
                ["nix-shell", "-p", "git", "--run",
                 f"git clone '{active_repo}' '{REPO_TMP}'"],
                env=env,
            )
            active_repo = REPO_TMP

        print()
        print("=== Provisioning disks ===")
        env = os.environ.copy()
        env["NIX_CONFIG"] = NIX_CONFIG
        run_sudo([
            "nix", "run", "github:nix-community/disko", "--",
            "--mode", "destroy,format,mount",
            "--arg", "disks", f'[ "{target_disk}" ]',
            str(active_repo / "hosts" / machine / "disko.nix"),
        ], env=env)

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
        env = os.environ.copy()
        env["NIX_CONFIG"] = NIX_CONFIG
        run_sudo(["nix", "run", "nixpkgs#sbctl", "--", "create-keys"], env=env)
        run_sudo(["umount", "/var/lib/sbctl"])

        print()
        print("=== Running nixos-install ===")
        env = os.environ.copy()
        env["NIX_CONFIG"] = NIX_CONFIG
        run_sudo([
            "nixos-install",
            "--flake", f"{active_repo}#{machine}",
        ], env=env)

        print()
        print("=== Install complete ===")
        print("Remove installation media and reboot.")

    finally:
        try:
            run_sudo(["shred", "-vfzu", str(passphrase_file)], check=False)
        except Exception:
            pass


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
    run_sudo(["sync"])
    print("Flash complete.")
    print()

    img_file.unlink(missing_ok=True)

    print("--- Installing age identity ---")
    print()

    run_sudo(["partprobe", target_dev])
    time.sleep(2)

    result = subprocess.run(
        ["lsblk", "-o", "NAME,FSTYPE", "--noheadings", target_dev],
        capture_output=True, text=True, check=True,
    )
    root_part = None
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[1] == "ext4":
            root_part = f"/dev/{parts[0]}"
            break

    if root_part is None:
        _die(f"Could not find an ext4 partition on {target_dev} after flashing.")

    print(f"Root partition: {root_part}")

    mnt_dir = Path(tempfile.mkdtemp())
    try:
        run_sudo(["mount", root_part, str(mnt_dir)])
        try:
            target_identity = mnt_dir / "var" / "lib" / "agenix" / "identity"
            install_age_identity(identity_file, target_identity)
        finally:
            run_sudo(["umount", str(mnt_dir)])
    finally:
        try:
            mnt_dir.rmdir()
        except OSError:
            pass

    print()
    print(f"=== Install complete: {machine} ===")
    print()
    print("Next steps:")
    print()
    print(f"  1. Eject the SD card, insert it into {machine}, connect ethernet, power on")
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


# ── Windows WSL flow ──────────────────────────────────────────────────────────

def _wsl_path(path: Path) -> str:
    """Convert a Windows absolute path to /mnt/<drive>/... for WSL."""
    abs_path = path.resolve()
    drive = abs_path.drive.rstrip(":").lower()
    rest = str(abs_path.relative_to(abs_path.anchor)).replace("\\", "/")
    return f"/mnt/{drive}/{rest}"


def _fetch_wsl_asset() -> tuple[str, str]:
    """Return (download_url, filename) for the latest NixOS-WSL .wsl asset."""
    req = urllib.request.Request(
        NIXOS_WSL_RELEASES_URL,
        headers={"Accept": "application/vnd.github+json", "User-Agent": "nixos-config-provision"},
    )
    with urllib.request.urlopen(req) as resp:
        release = json.loads(resp.read())

    assets = [
        a for a in release["assets"]
        if a["name"].endswith(".wsl") and not a["name"].endswith(".sha256")
    ]
    if not assets:
        names = [a["name"] for a in release["assets"]]
        _die(f"No .wsl asset found in latest NixOS-WSL release. Assets: {', '.join(names)}")

    asset = assets[0]
    return asset["browser_download_url"], asset["name"]


def _resize_wsl_vhd(install_dir: Path, size_gb: int) -> None:
    vhd_path = install_dir / "ext4.vhdx"
    if not vhd_path.exists():
        print(f"Warning: VHD not found at {vhd_path} — skipping resize.")
        return

    result = subprocess.run(
        ["powershell.exe", "-NoProfile", "-Command",
         f"(Get-VHD -Path '{vhd_path}').Size"],
        capture_output=True, text=True, check=False,
    )
    if result.returncode != 0 or not result.stdout.strip().isdigit():
        print(f"Warning: Could not query VHD size — skipping resize.")
        return

    current_gb = int(result.stdout.strip()) // (1024 ** 3)
    requested_bytes = size_gb * 1024 ** 3

    if current_gb >= size_gb:
        print(
            f"Warning: VHD is already {current_gb} GB — requested {size_gb} GB is not larger. "
            "Skipping resize."
        )
        return

    subprocess.run(["wsl.exe", "--terminate", WSL_DISTRO_NAME], capture_output=True)

    result = subprocess.run(
        ["powershell.exe", "-NoProfile", "-Command",
         f"Resize-VHD -Path '{vhd_path}' -SizeBytes {requested_bytes}"],
        capture_output=True, text=True, check=False,
    )
    if result.returncode != 0:
        print(f"Warning: Resize-VHD failed — VHD remains at {current_gb} GB.")
        if result.stderr.strip():
            print(f"  {result.stderr.strip()}")
    else:
        print(f"VHD resized to {size_gb} GB.")


def _wsl_flow(machine: str, flake_branch: str = "") -> None:
    if subprocess.run(["wsl.exe", "--version"], capture_output=True).returncode != 0:
        _die("wsl.exe not found or WSL2 not enabled.\nRun: wsl --install    then reboot.")

    flake_repo = (
        f"github:geoff-coppertop/nixos-config/{flake_branch}"
        if flake_branch
        else "github:geoff-coppertop/nixos-config"
    )

    # ── age identity ──────────────────────────────────────────────────────────

    age_identity: Path | None = None
    print("Age identity key source:")
    print("  1) File path")
    print("  2) Skip (enroll post-boot)")
    print()
    choice = input("Choice [1/2]: ").strip()
    if choice == "1":
        raw = input("Path to age identity file: ").strip()
        age_identity = Path(raw)
        if not age_identity.exists():
            _die(f"Age identity file not found: {age_identity}")
    elif choice == "2":
        age_identity = None
    else:
        _die("Invalid choice.")

    # ── disk size ─────────────────────────────────────────────────────────────

    print()
    raw_size = input(f"VHD size in GB [{WSL_DEFAULT_DISK_SIZE_GB}]: ").strip()
    if raw_size == "":
        disk_size_gb = WSL_DEFAULT_DISK_SIZE_GB
    elif raw_size.isdigit() and int(raw_size) > 0:
        disk_size_gb = int(raw_size)
    else:
        _die(f"Invalid disk size: '{raw_size}' — enter a positive integer.")

    # ── download + import ──────────────────────────────────────────────────────

    print()
    print("Fetching latest NixOS-WSL release...")
    url, filename = _fetch_wsl_asset()

    install_dir = Path(os.environ["LOCALAPPDATA"]) / WSL_DISTRO_NAME
    install_dir.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as tmp:
        image_path = Path(tmp) / filename
        print(f"Downloading {url} ...")
        urllib.request.urlretrieve(url, image_path)

        print()
        print(f"Importing as WSL distro '{WSL_DISTRO_NAME}'...")
        result = subprocess.run(
            ["wsl.exe", "--import", WSL_DISTRO_NAME, str(install_dir), str(image_path)],
            check=False,
        )
        if result.returncode != 0:
            _die(f"wsl --import failed (exit {result.returncode})")

    # ── resize VHD ────────────────────────────────────────────────────────────

    print()
    print(f"Resizing VHD to {disk_size_gb} GB...")
    _resize_wsl_vhd(install_dir, disk_size_gb)

    # ── age identity ──────────────────────────────────────────────────────────

    if age_identity is not None:
        print()
        print("Installing age identity...")
        wsl_path = _wsl_path(age_identity)
        subprocess.run(
            ["wsl.exe", "-d", WSL_DISTRO_NAME, "--", "bash", "-c",
             f"sudo mkdir -p -m 700 /var/lib/agenix "
             f"&& sudo cp '{wsl_path}' /var/lib/agenix/identity "
             f"&& sudo chmod 400 /var/lib/agenix/identity"],
            check=True,
        )
        print("Age identity installed.")
        print(f"Remember to delete {age_identity} from Windows after provisioning.")

    # ── apply flake config ─────────────────────────────────────────────────────

    if age_identity is None:
        print()
        print("=== Distro imported. Age identity not provided — skipping nixos-rebuild. ===")
        print()
        print(f"The {machine} config uses agenix secrets. nixos-rebuild requires")
        print("the age private key at /var/lib/agenix/identity before it can succeed.")
        print()
        print("To complete setup, copy the age identity then rerun:")
        print()
        print(f"  scp thomasga@enterprise-d:~/.config/agenix/{machine}.age %TEMP%\\{machine}.age")
        print(f"  python tools\\install.py")
        return

    print()
    print(f"Applying {machine} configuration (this may take several minutes)...")
    result = subprocess.run(
        ["wsl.exe", "-d", WSL_DISTRO_NAME, "--", "bash", "-c",
         f"sudo nixos-rebuild switch --flake '{flake_repo}#{machine}'"],
        check=False,
    )
    if result.returncode != 0:
        print()
        print("nixos-rebuild failed. The distro was imported and the age identity was installed.")
        print("To retry:")
        print(f"  wsl -d {WSL_DISTRO_NAME} -- bash -c "
              f"\"sudo nixos-rebuild switch --flake '{flake_repo}#{machine}'\"")
        sys.exit(1)

    print()
    print(f"=== Setup complete. Launch NixOS WSL with: wsl -d {WSL_DISTRO_NAME} ===")


# ── entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    if not IS_WINDOWS:
        os.environ["NIX_CONFIG"] = NIX_CONFIG

    print("=== NixOS Install ===")
    print()

    root = repo_root()
    in_repo = root is not None

    if IS_WINDOWS:
        if not in_repo:
            _die("Run from inside the nixos-config repo checkout.")
        hosts_dir = root / "hosts"
    else:
        if not in_repo:
            print("Not inside a git repo — this looks like a live USB session.")
            print()
            repo_url = input(f"Git repo URL [{DEFAULT_REPO_URL}]: ").strip() or DEFAULT_REPO_URL
            print()
            print("=== Cloning repo ===")
            run_sudo(["rm", "-rf", str(REPO_TMP)])
            env = os.environ.copy()
            env["NIX_CONFIG"] = NIX_CONFIG
            run_sudo(
                ["nix-shell", "-p", "git", "--run",
                 f"git clone '{repo_url}' '{REPO_TMP}'"],
                env=env,
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

    if not IS_WINDOWS:
        identity_file = Path.home() / ".config" / "agenix" / f"{machine}.age"
        secrets_nix = (root if in_repo else REPO_TMP) / "secrets" / "secrets.nix"
        already_enrolled = (
            identity_file.exists()
            and f'  {machine} = "age1' in secrets_nix.read_text()
        )
        if not already_enrolled:
            print(f"--- {machine} is not enrolled — running enrollment first ---")
            print()
            enroll_machine(machine)
            print()

    if mtype == "disko":
        active_repo = root if in_repo else REPO_TMP
        _disko_flow(machine, active_repo, in_repo)
    elif mtype == "sd-card":
        _sdcard_flow(machine, root)
    elif mtype == "wsl":
        _wsl_flow(machine)


if __name__ == "__main__":
    main()
