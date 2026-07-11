#!/usr/bin/env python3
"""
install_age_identity.py

Copies an age identity key to a NixOS system's agenix identity path.
Defaults to /mnt/var/lib/agenix/identity (for use during provisioning).
Use --target to override for an already-installed system.

Source options (provide exactly one):
  --device <partition>   USB partition containing nixos-config.age at its root
  --file   <path>        Direct path to the key file on the current filesystem.

Optional flags:
  --target <path>        Override the destination path.
  --shred                Shred the source key after copying.

Must be run as root (use sudo) when using --device or writing to system paths.
"""

import argparse
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from common import die, run, run_sudo


TARGET_KEY_DEFAULT = Path("/mnt/var/lib/agenix/identity")
USB_MOUNT = Path("/mnt/usb-secrets")
KEY_FILENAME = "nixos-config.age"


def install_age_identity(
    source_file: Path,
    target: Path = TARGET_KEY_DEFAULT,
    shred: bool = False,
) -> None:
    """Install an age identity key to target path. source_file must exist."""
    if not source_file.exists():
        die(f"Key file '{source_file}' does not exist.")

    print(f"Installing key to {target}...")
    target.parent.mkdir(parents=True, exist_ok=True)
    run(["install", "-D", "-m", "600", str(source_file), str(target)])

    if not target.exists():
        die(f"Key was not written to {target}.")

    print("Key installed successfully.")

    if shred:
        print("Shredding source key...")
        run(["shred", "-vfzu", str(source_file)])
        print("Source key shredded.")


def _install_from_device(
    device: str,
    target: Path,
    shred: bool,
) -> None:
    """Mount device, copy key, optionally shred, unmount."""
    if not Path(device).is_block_device():
        die(f"Device '{device}' does not exist or is not a block device.")

    print(f"Mounting {device} at {USB_MOUNT} (read-only)...")
    USB_MOUNT.mkdir(parents=True, exist_ok=True)
    try:
        run_sudo(["mount", "-o", "ro", device, str(USB_MOUNT)])
        source_key = USB_MOUNT / KEY_FILENAME
        if not source_key.exists():
            run_sudo(["umount", str(USB_MOUNT)])
            USB_MOUNT.rmdir()
            die(f"Key file '{KEY_FILENAME}' not found on {device}.")

        install_age_identity(source_key, target, shred=False)

        if shred:
            print(f"Remounting {device} read-write to shred source key...")
            run_sudo(["mount", "-o", "remount,rw", str(USB_MOUNT)])
            print("Shredding source key...")
            run(["shred", "-vfzu", str(source_key)])
            print("Source key shredded.")
            print(
                "NOTE: Flash storage uses wear leveling. "
                "Reformat the USB before reusing it for sensitive material."
            )
    finally:
        print(f"Unmounting {device}...")
        run_sudo(["umount", str(USB_MOUNT)], check=False)
        try:
            USB_MOUNT.rmdir()
        except OSError:
            pass

    print("Done.")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Install an age identity key to a NixOS system.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument(
        "--device",
        metavar="PARTITION",
        help=f"USB partition containing {KEY_FILENAME} at its root",
    )
    source.add_argument(
        "--file",
        metavar="PATH",
        help="Direct path to the key file",
    )
    parser.add_argument(
        "--target",
        metavar="PATH",
        default=str(TARGET_KEY_DEFAULT),
        help=f"Destination path (default: {TARGET_KEY_DEFAULT})",
    )
    parser.add_argument(
        "--shred",
        action="store_true",
        help="Shred the source key after copying",
    )
    args = parser.parse_args()

    target = Path(args.target)

    if args.device:
        if os.geteuid() != 0:
            die("--device mode must be run as root (use sudo).")
        _install_from_device(args.device, target, args.shred)
    else:
        source_file = Path(args.file)
        install_age_identity(source_file, target, shred=args.shred)
        print("Done.")


if __name__ == "__main__":
    main()
