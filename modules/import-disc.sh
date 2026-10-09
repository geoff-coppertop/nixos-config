#!/usr/bin/env bash
# Import already-ripped video files from a data disc (e.g. a DVD burned with
# DivX/Xvid rips) into custom.mediaRipping.importDir, bucketed by type so
# custom.mediaSort's importDir leg can push it straight into the library on
# its next run -- no separate "run tmm afterwards" step. Unlike rip-disc/ARM,
# the disc already holds finished video files on an ISO9660/UDF filesystem --
# no MakeMKV decrypt or HandBrake transcode needed, just mount and copy.
#
# There is no metadata source here (no TMDB lookup like ARM, no job
# database), so movie-vs-tv and, for tv, show/season are the one thing this
# script can't work out on its own -- the operator supplies them.

set -euo pipefail

import_root="${IMPORT_ROOT:?IMPORT_ROOT must be set (custom.mediaRipping.importDir)}"
import_uid="${IMPORT_UID:?IMPORT_UID must be set}"
import_gid="${IMPORT_GID:?IMPORT_GID must be set}"
extensions="avi divx mkv mp4 mpg mpeg wmv m4v mov"

usage() {
  echo "Usage:"
  echo "  import-disc --type movie [--title NAME] [DEVICE]"
  echo "  import-disc --type tv --show NAME --season N [DEVICE]"
  echo
  echo "  Mounts the data disc in DEVICE (default: /dev/sr0), copies any video"
  echo "  files (${extensions// /, }) into \$IMPORT_ROOT/movies/<title>/ or"
  echo "  \$IMPORT_ROOT/tv/<show>/Season N/, then unmounts and ejects."
  echo "  custom.mediaSort picks both up on its next run -- no further step."
}

media_type=""
title=""
show=""
season=""
device="/dev/sr0"

while [ $# -gt 0 ]; do
  case "$1" in
    --type)
      media_type="$2"
      shift 2
      ;;
    --title)
      title="$2"
      shift 2
      ;;
    --show)
      show="$2"
      shift 2
      ;;
    --season)
      season="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      device="$1"
      shift
      ;;
  esac
done

case "$media_type" in
  movie) ;;
  tv)
    if [ -z "$show" ] || [ -z "$season" ]; then
      echo "error: --type tv requires --show and --season" >&2
      usage
      exit 1
    fi
    ;;
  *)
    echo "error: --type movie|tv is required" >&2
    usage
    exit 1
    ;;
esac

if [ "$(id -u)" -ne 0 ]; then
  echo "import-disc must run as root (mount/umount need it): sudo import-disc" >&2
  exit 1
fi

if [ "$media_type" = movie ]; then
  output_dir="$import_root/movies/${title:-import-$(date +%Y%m%d-%H%M%S)}"
else
  output_dir="$import_root/tv/$show/Season $season"
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

# custom.mediaSort runs as import_uid/import_gid and needs to read, rsync,
# and delete these -- root's own ownership from the cp above would block that.
chown -R "$import_uid:$import_gid" "$output_dir"

echo "==> Ejecting..."
umount "$mount_point"
eject "$device" 2>/dev/null || true

echo "==> Done. $copied file(s) copied to $output_dir."
echo "    custom.mediaSort will push this into the library on its next run."
