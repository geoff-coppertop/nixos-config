#!/usr/bin/env bash
# nixos-install.sh

set -euo pipefail

export NIX_CONFIG="experimental-features = nix-command flakes"

REPO_URL="https://github.com/geoff-coppertop/nixos-config"
REPO_TMP="/tmp/nixos-config"
REPO_TARGET="/mnt/etc/nixos/nixos-config"
KEY_FILENAME="nixos-config.age"

# ------------------------------------------------------------------------------
# helpers
# ------------------------------------------------------------------------------

prompt() {
  local var_name="$1"
  local message="$2"
  local default="${3:-}"
  local value

  if [[ -n "$default" ]]; then
    read -rp "$message [$default]: " value
    value="${value:-$default}"
  else
    read -rp "$message: " value
  fi

  if [[ -z "$value" ]]; then
    echo "Error: value required." >&2
    exit 1
  fi

  printf -v "$var_name" '%s' "$value"
}

prompt_secret() {
  local var_name="$1"
  local message="$2"
  local value
  local confirm

  while true; do
    read -rsp "$message: " value
    echo

    [[ -z "$value" ]] && continue

    read -rsp "Confirm: " confirm
    echo

    if [[ "$value" == "$confirm" ]]; then
      break
    fi

    echo "Passphrases do not match."
  done

  printf -v "$var_name" '%s' "$value"
}

# ------------------------------------------------------------------------------
# inputs
# ------------------------------------------------------------------------------

echo "=== NixOS Installer ==="
echo

lsblk -d -o NAME,SIZE,MODEL
echo

DETECTED_DISK=$(
  lsblk -d -o NAME,TYPE --noheadings \
    | awk '$2=="disk" {print "/dev/"$1}' \
    | head -1
)

prompt REPO_URL "Git repo URL" "$REPO_URL"
prompt TARGET_DISK "Target disk device" "${DETECTED_DISK:-}"

if [[ ! -b "$TARGET_DISK" ]]; then
  echo "Error: $TARGET_DISK is not a block device." >&2
  exit 1
fi

prompt_secret LUKS_PASSPHRASE "LUKS passphrase"

echo
echo "Age identity key source:"
echo "  1) USB drive"
echo "  2) File path"
echo "  3) Skip"

read -rp "Choice [1/2/3]: " KEY_SOURCE_CHOICE

KEY_DEVICE=""
KEY_FILE_PATH=""

case "$KEY_SOURCE_CHOICE" in
  1)
    echo
    echo "Insert the USB drive containing $KEY_FILENAME and press Enter."
    read -r

    DETECTED_KEY_DEV=$(
      lsblk -d -o NAME,RM,TYPE --noheadings \
        | awk '$2=="1" && $3=="disk" {print "/dev/"$1"1"}' \
        | head -1
    )

    prompt KEY_DEVICE "Key USB partition" "${DETECTED_KEY_DEV:-}"
    ;;

  2)
    prompt KEY_FILE_PATH \
      "Absolute path to the key file" \
      "/run/media/nixos/keys/$KEY_FILENAME"
    ;;

  3)
    echo "Skipping age identity install."
    ;;

  *)
    echo "Invalid choice." >&2
    exit 1
    ;;
esac

KEY_SHRED_ARGS=""

if [[ "$KEY_SOURCE_CHOICE" != "3" ]]; then
  read -rp "Shred source key after copy? [y/N]: " shred_choice

  if [[ "$shred_choice" =~ ^[Yy]$ ]]; then
    KEY_SHRED_ARGS="--shred"
  fi
fi

# ------------------------------------------------------------------------------
# secure live environment
# ------------------------------------------------------------------------------

echo
echo "=== Securing live session ==="

# Lock the live user account — no password needed since we won't use SSH
sudo passwd -l nixos

# ------------------------------------------------------------------------------
# write passphrase file — trap ensures it is shredded even on failure
# ------------------------------------------------------------------------------

PASSPHRASE_FILE="/tmp/encryption-password"

touch "$PASSPHRASE_FILE"
chmod 600 "$PASSPHRASE_FILE"
printf '%s' "$LUKS_PASSPHRASE" > "$PASSPHRASE_FILE"
unset LUKS_PASSPHRASE

trap 'sudo shred -vfzu "$PASSPHRASE_FILE" 2>/dev/null || true' EXIT

# ------------------------------------------------------------------------------
# clone repo as root so it is never world-readable in /tmp
# ------------------------------------------------------------------------------

echo
echo "=== Cloning repo ==="

sudo rm -rf "$REPO_TMP"

sudo NIX_CONFIG="$NIX_CONFIG" \
  nix-shell -p git --run \
  "git clone '$REPO_URL' '$REPO_TMP'"

# ------------------------------------------------------------------------------
# select host
# ------------------------------------------------------------------------------

echo
echo "=== Select target host ==="

mapfile -t AVAILABLE_HOSTS < <(
  find "$REPO_TMP/hosts" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    -printf '%f\n' \
    | sort
)

if [[ ${#AVAILABLE_HOSTS[@]} -eq 0 ]]; then
  echo "No hosts found." >&2
  exit 1
fi

for i in "${!AVAILABLE_HOSTS[@]}"; do
  echo "  $((i+1))) ${AVAILABLE_HOSTS[$i]}"
done

echo

while true; do
  read -rp "Select host [1-${#AVAILABLE_HOSTS[@]}] [1]: " host_choice

  host_choice="${host_choice:-1}"

  if [[ "$host_choice" =~ ^[0-9]+$ ]] &&
     (( host_choice >= 1 && host_choice <= ${#AVAILABLE_HOSTS[@]} ))
  then
    FLAKE_TARGET="${AVAILABLE_HOSTS[$((host_choice-1))]}"
    break
  fi

  echo "Invalid selection."
done

echo "Installing host: $FLAKE_TARGET"

if [[ ! -f "$REPO_TMP/hosts/$FLAKE_TARGET/disko.nix" ]]; then
  echo
  echo "Host '$FLAKE_TARGET' is not a physical machine (no disko.nix found)."
  echo "For WSL machines, use tools/install-wsl.ps1 on your Windows host."
  exit 1
fi

# ------------------------------------------------------------------------------
# disko
# ------------------------------------------------------------------------------

echo
echo "=== Provisioning disks ==="

sudo NIX_CONFIG="$NIX_CONFIG" \
  nix run github:nix-community/disko -- \
  --mode destroy,format,mount \
  --arg disks "[ \"$TARGET_DISK\" ]" \
  "$REPO_TMP/hosts/$FLAKE_TARGET/disko.nix"

# ------------------------------------------------------------------------------
# verify mounts
# ------------------------------------------------------------------------------

echo
echo "=== Verifying mounts ==="

findmnt /mnt
findmnt /mnt/boot

# ------------------------------------------------------------------------------
# copy repo
# ------------------------------------------------------------------------------

echo
echo "=== Copying repo ==="

sudo mkdir -p -m 0700 /mnt/etc/nixos

sudo cp -r "$REPO_TMP" "$REPO_TARGET"

sudo chown -R root:root "$REPO_TARGET"

# ------------------------------------------------------------------------------
# install age identity
# ------------------------------------------------------------------------------

if [[ "$KEY_SOURCE_CHOICE" != "3" ]]; then
  echo
  echo "=== Installing age identity ==="

  if [[ -n "$KEY_DEVICE" ]]; then
    sudo bash \
      "$REPO_TARGET/tools/install-age-identity.sh" \
      --device "$KEY_DEVICE" \
      $KEY_SHRED_ARGS
  else
    sudo bash \
      "$REPO_TARGET/tools/install-age-identity.sh" \
      --file "$KEY_FILE_PATH" \
      $KEY_SHRED_ARGS
  fi
fi

# ------------------------------------------------------------------------------
# secure boot keys
# ------------------------------------------------------------------------------

echo
echo "=== Initializing Secure Boot Keys ==="

sudo mkdir -p -m 0700 /mnt/etc/secureboot

sudo mkdir -p -m 0700 /var/lib/sbctl

sudo mount --bind /mnt/etc/secureboot /var/lib/sbctl

sudo NIX_CONFIG="$NIX_CONFIG" \
  nix run nixpkgs#sbctl -- create-keys

sudo umount /var/lib/sbctl

# ------------------------------------------------------------------------------
# install nixos
# ------------------------------------------------------------------------------

echo
echo "=== Running nixos-install ==="

# Install from the cloned repo in /tmp rather than the copy in /mnt,
# so a partial copy cannot produce a broken install.
sudo NIX_CONFIG="$NIX_CONFIG" \
  nixos-install --flake "$REPO_TMP#$FLAKE_TARGET"

echo
echo "=== Install complete ==="
echo "Remove installation media and reboot."
