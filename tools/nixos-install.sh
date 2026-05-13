#!/usr/bin/env bash
# nixos-install.sh
#
# Interactive NixOS installer for any host defined in this repo.
#
# Prompts for the minimum required inputs, then:
#   1. Secures the live session
#   2. Prepares the target directory
#   3. Clones the repo
#   4. Selects the target host from available hosts in the repo
#   5. Runs disko to partition, format, and mount the disk
#   6. Installs the age identity key (optional)
#   7. Runs nixos-install
#
# Run as the nixos user from the live installer:
#   bash tools/nixos-install.sh
#
# WARNING: disko will DESTROY all data on the selected disk.
export NIX_CONFIG="experimental-features = nix-command flakes"

set -euo pipefail

REPO_URL=https://github.com/geoff-coppertop/nixos-config
REPO_TARGET=/mnt/etc/nixos/nixos-config
KEY_FILENAME=nixos-config.age

# ── helpers ──────────────────────────────────────────────────────────────────

prompt() {
  local var_name="$1"
  local message="$2"
  local value
  read -rp "$message: " value
  if [[ -z "$value" ]]; then
    echo "Error: value required." >&2
    exit 1
  fi
  printf -v "$var_name" '%s' "$value"
}

prompt_secret() {
  local var_name="$1"
  local message="$2"
  local value value2
  read -rsp "$message: " value
  echo
  read -rsp "Confirm: " value2
  echo
  if [[ "$value" != "$value2" ]]; then
    echo "Error: values do not match." >&2
    exit 1
  fi
  if [[ -z "$value" ]]; then
    echo "Error: value required." >&2
    exit 1
  fi
  printf -v "$var_name" '%s' "$value"
}

confirm_destructive() {
  local disk="$1"
  echo
  echo "WARNING: ALL DATA ON $disk WILL BE DESTROYED."
  read -rp "Type the device path again to confirm: " confirm
  if [[ "$confirm" != "$disk" ]]; then
    echo "Aborted." >&2
    exit 1
  fi
}

# ── gather inputs ─────────────────────────────────────────────────────────────

echo "=== NixOS Installer ==="
echo

lsblk -d -o NAME,SIZE,MODEL
echo

prompt REPO_URL   "Git repo URL (e.g. https://github.com/you/nixos-config)"
prompt TARGET_DISK "Target disk device (e.g. /dev/nvme0n1)"
prompt_secret LUKS_PASSPHRASE "LUKS passphrase"

# Host is selected after cloning (see step 3 below)
FLAKE_TARGET=

echo
echo "Age identity key source:"
echo "  1) USB drive  — mount a partition containing $KEY_FILENAME"
echo "  2) File path  — provide an absolute path to the key file"
echo "  3) Skip       — install the key manually after reboot"
read -rp "Choice [1/2/3]: " KEY_SOURCE_CHOICE

KEY_DEVICE=
KEY_FILE_PATH=
case "$KEY_SOURCE_CHOICE" in
  1)
    echo
    echo "Insert the USB drive containing $KEY_FILENAME and press Enter."
    read -r
    lsblk -d -o NAME,SIZE,MODEL
    echo
    prompt KEY_DEVICE "Key USB partition (e.g. /dev/sdb1)"
    ;;
  2)
    echo
    prompt KEY_FILE_PATH "Absolute path to the key file (e.g. /run/media/nixos/keys/$KEY_FILENAME)"
    ;;
  3)
    echo "Skipping age identity install."
    ;;
  *)
    echo "Invalid choice '$KEY_SOURCE_CHOICE'. Aborting." >&2
    exit 1
    ;;
esac

KEY_SHRED_ARGS=
if [[ "$KEY_SOURCE_CHOICE" != "3" ]]; then
  read -rp "Shred the source key after copying? [y/N]: " shred_choice
  [[ "$shred_choice" =~ ^[Yy]$ ]] && KEY_SHRED_ARGS="--shred"
fi

# ── step 1: secure the live session ──────────────────────────────────────────

echo
echo "=== Securing live session ==="
passwd nixos

# ── step 2: prepare the target directory ─────────────────────────────────────

echo
echo "=== Preparing target directory ==="
sudo mkdir -p -m 0700 /mnt/etc/nixos
sudo chown nixos:users /mnt/etc/nixos

# ── step 3: clone the repo ────────────────────────────────────────────────────

echo
echo "=== Cloning repo ==="
nix-shell -p git --run "git clone '$REPO_URL' '$REPO_TARGET'"

# ── step 5: select host ───────────────────────────────────────────────────────

echo
echo "=== Select target host ==="
mapfile -t AVAILABLE_HOSTS < <(find "$REPO_TARGET/hosts" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)

if [[ ${#AVAILABLE_HOSTS[@]} -eq 0 ]]; then
  echo "Error: no hosts found in $REPO_TARGET/hosts." >&2
  exit 1
fi

echo "Available hosts:"
for i in "${!AVAILABLE_HOSTS[@]}"; do
  echo "  $((i+1))) ${AVAILABLE_HOSTS[$i]}"
done
echo

while true; do
  read -rp "Select host [1-${#AVAILABLE_HOSTS[@]}]: " host_choice
  if [[ "$host_choice" =~ ^[0-9]+$ ]] && (( host_choice >= 1 && host_choice <= ${#AVAILABLE_HOSTS[@]} )); then
    FLAKE_TARGET="${AVAILABLE_HOSTS[$((host_choice-1))]}"
    break
  fi
  echo "Invalid selection. Enter a number between 1 and ${#AVAILABLE_HOSTS[@]}."
done

echo "Installing host: $FLAKE_TARGET"

# ── step 5: provision disks ───────────────────────────────────────────────────

echo
echo "=== Provisioning disks ==="
confirm_destructive "$TARGET_DISK"

PASSPHRASE_FILE=$(mktemp)
chmod 600 "$PASSPHRASE_FILE"
printf '%s' "$LUKS_PASSPHRASE" > "$PASSPHRASE_FILE"
unset LUKS_PASSPHRASE

sudo nix run github:nix-community/disko -- \
  --mode destroy,format,mount \
  "$REPO_TARGET/hosts/$FLAKE_TARGET/disko.nix"

sudo shred -vfzu "$PASSPHRASE_FILE"

# ── step 6: install age identity ─────────────────────────────────────────────

if [[ "$KEY_SOURCE_CHOICE" != "3" ]]; then
  echo
  echo "=== Installing age identity ==="
  if [[ -n "$KEY_DEVICE" ]]; then
    sudo bash "$REPO_TARGET/tools/install-age-identity.sh" --device "$KEY_DEVICE" $KEY_SHRED_ARGS
  else
    sudo bash "$REPO_TARGET/tools/install-age-identity.sh" --file "$KEY_FILE_PATH" $KEY_SHRED_ARGS
  fi
else
  echo
  echo "=== Skipping age identity install ==="
  echo "Install it later with:"
  echo "  sudo install -D -m 600 /path/to/$KEY_FILENAME /var/lib/agenix/identity"
fi

# ── step 7: install ───────────────────────────────────────────────────────────

echo
echo "=== Running nixos-install ==="
sudo nixos-install --flake "$REPO_TARGET#$FLAKE_TARGET"

echo
echo "=== Install complete. Remove USB drives and reboot. ==="
