#!/usr/bin/env bash
# install-age-identity.sh
#
# Copies an age identity key to a NixOS system's agenix identity path.
# Defaults to /mnt/var/lib/agenix/identity (for use during provisioning).
# Use --target to override for an already-installed system.
#
# Source options (provide exactly one):
#   --device <partition>   USB partition containing nixos-config.age at its root
#                          (e.g. /dev/sdb1). Run `lsblk` to identify it.
#   --file   <path>        Direct path to the key file on the current filesystem.
#
# Optional flags:
#   --target <path>        Override the destination path.
#                          Default: /mnt/var/lib/agenix/identity
#                          Running system: /var/lib/agenix/identity
#   --shred                Shred the source key after copying.
#                          NOTE: Flash storage uses wear leveling — shredding is
#                          best-effort. Reformat the USB before reusing it for
#                          sensitive material.
#
# Must be run as root (use sudo).

set -euo pipefail

TARGET_KEY=/mnt/var/lib/agenix/identity
USB_MOUNT=/mnt/usb-secrets
KEY_FILENAME=nixos-config.age

SOURCE_DEVICE=
SOURCE_FILE=
DO_SHRED=false

# ── parse arguments ───────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device)
      SOURCE_DEVICE="$2"; shift 2 ;;
    --file)
      SOURCE_FILE="$2"; shift 2 ;;
    --target)
      TARGET_KEY="$2"; shift 2 ;;
    --shred)
      DO_SHRED=true; shift ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: sudo bash $0 {--device <partition> | --file <path>} [--target <path>] [--shred]" >&2
      exit 1 ;;
  esac
done

if [[ -z "$SOURCE_DEVICE" && -z "$SOURCE_FILE" ]]; then
  echo "Error: provide --device <partition> or --file <path>." >&2
  echo "Usage: sudo bash $0 {--device <partition> | --file <path>} [--target <path>] [--shred]" >&2
  exit 1
fi

if [[ -n "$SOURCE_DEVICE" && -n "$SOURCE_FILE" ]]; then
  echo "Error: --device and --file are mutually exclusive." >&2
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root (use sudo)." >&2
  exit 1
fi

# ── resolve source key path ───────────────────────────────────────────────────

if [[ -n "$SOURCE_DEVICE" ]]; then
  if [[ ! -b "$SOURCE_DEVICE" ]]; then
    echo "Device '$SOURCE_DEVICE' does not exist or is not a block device." >&2
    exit 1
  fi

  echo "Mounting $SOURCE_DEVICE at $USB_MOUNT (read-only)..."
  mkdir -p "$USB_MOUNT"
  mount -o ro "$SOURCE_DEVICE" "$USB_MOUNT"

  SOURCE_KEY="$USB_MOUNT/$KEY_FILENAME"

  if [[ ! -f "$SOURCE_KEY" ]]; then
    echo "Key file '$KEY_FILENAME' not found on $SOURCE_DEVICE." >&2
    umount "$USB_MOUNT"
    rmdir "$USB_MOUNT"
    exit 1
  fi
else
  SOURCE_KEY="$SOURCE_FILE"

  if [[ ! -f "$SOURCE_KEY" ]]; then
    echo "Key file '$SOURCE_KEY' does not exist." >&2
    exit 1
  fi
fi

# ── copy key ──────────────────────────────────────────────────────────────────

echo "Installing key to $TARGET_KEY..."
install -D -m 600 "$SOURCE_KEY" "$TARGET_KEY"

if [[ ! -f "$TARGET_KEY" ]]; then
  echo "Key was not written to $TARGET_KEY." >&2
  [[ -n "$SOURCE_DEVICE" ]] && { umount "$USB_MOUNT"; rmdir "$USB_MOUNT"; }
  exit 1
fi

echo "Key installed successfully."

# ── optionally shred source ───────────────────────────────────────────────────

if [[ "$DO_SHRED" == true ]]; then
  if [[ -n "$SOURCE_DEVICE" ]]; then
    echo "Remounting $SOURCE_DEVICE read-write to shred source key..."
    mount -o remount,rw "$USB_MOUNT"
  fi

  echo "Shredding source key..."
  shred -vfzu "$SOURCE_KEY"
  echo "Source key shredded."

  if [[ -n "$SOURCE_DEVICE" ]]; then
    echo "NOTE: Flash storage uses wear leveling. Reformat the USB before reusing it for sensitive material."
  fi
fi

# ── unmount USB if used ───────────────────────────────────────────────────────

if [[ -n "$SOURCE_DEVICE" ]]; then
  echo "Unmounting $SOURCE_DEVICE..."
  umount "$USB_MOUNT"
  rmdir "$USB_MOUNT"
fi

echo "Done."
