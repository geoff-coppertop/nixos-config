#!/usr/bin/env bash
# Import already-ripped video files from a data disc (e.g. a DVD burned with
# DivX/Xvid rips) into the media library staging area. Unlike rip-disc/ARM,
# the disc already holds finished video files on an ISO9660/UDF filesystem —
# no MakeMKV decrypt or HandBrake transcode needed, just mount and copy.

set -euo pipefail

output_dir="${IMPORT_OUTPUT_DIR:-$PWD}"
device="${1:-/dev/sr0}"
extensions="avi divx mkv mp4 mpg mpeg wmv m4v mov"

usage() {
  echo "Usage: import-disc [DEVICE]"
  echo
  echo "  Mounts the data disc in DEVICE (default: /dev/sr0), copies any video"
  echo "  files (${extensions// /, }) to \$IMPORT_OUTPUT_DIR (default: \$PWD),"
  echo "  then unmounts and ejects."
  echo
  echo "  Run tinyMediaManager afterwards to identify and rename the copies."
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "import-disc must run as root (mount/umount need it): sudo import-disc" >&2
  exit 1
fi

mount_point="$(mktemp -d)"
cleanup() {
  umount "$mount_point" 2>/dev/null || true
  rmdir "$mount_point" 2>/dev/null || true
}
trap cleanup EXIT

echo "==> Mounting $device..."
mount -o ro "$device" "$mount_point"

mkdir -p "$output_dir"

find_args=()
for ext in $extensions; do
  find_args+=(-o -iname "*.$ext")
done
find_args=("${find_args[@]:1}") # drop the leading -o

echo "==> Copying video files to $output_dir..."
copied=0
while IFS= read -r -d '' f; do
  echo "    $(basename "$f")"
  cp -n "$f" "$output_dir/"
  copied=$((copied + 1))
done < <(find "$mount_point" -type f \( "${find_args[@]}" \) -print0)

if [ "$copied" -eq 0 ]; then
  echo "No video files found on disc." >&2
  exit 1
fi

echo "==> Ejecting..."
umount "$mount_point"
eject "$device" 2>/dev/null || true

echo "==> Done. $copied file(s) copied to $output_dir."
echo "    Run tinyMediaManager (library.coppertop.ca) to identify and rename them."
