#!/usr/bin/env bash
# nixos-install.sh
#
# Interactive NixOS installer for any host defined in this repo.
#
# Prompts for the minimum required inputs, then:
#   1. Secures the live session
#   2. Clones the repo to a temporary RAM drive
#   3. Selects the target host from available hosts in the repo
#   4. Runs disko to partition, format, and mount the disk to /mnt
#   5. Copies the repo into the newly mounted /mnt
#   6. Installs the age identity key (optional)
#   7. Runs nixos-install
#
# WARNING: disko will DESTROY all data on the selected disk.
export NIX_CONFIG="experimental-features = nix-command flakes"

set -euo pipefail

export NIX_CONFIG="experimental-features = nix-command flakes"

REPO_URL=https://github.com/geoff-coppertop/nixos-config
REPO_TMP=/tmp/nixos-config
REPO_TARGET=/mnt/etc/nixos/nixos-config
KEY_FILENAME=nixos-config.age

# -- helpers ------------------------------------------------------------------

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
  local value value2
  while true; do
    read -rsp "$message: " value
    echo
    if [[ -z "$value" ]]; then
      echo "Error: value required." >&2
      continue
    fi
    read -rsp "Confirm: " value2
    echo
    if [[ "$value" != "$value2" ]]; then
      echo "Passphrases do not match, try again." >&2
      continue
    fi
    break
  done
  printf -v "$var_name" '%s' "$value"
}

# -- gather inputs -------------------------------------------------------------

echo "=== NixOS Installer ==="
echo

lsblk -d -o NAME,SIZE,MODEL
echo

DETECTED_DISK=$(lsblk -d -o NAME,TYPE --noheadings | awk '$2=="disk" {print "/dev/"$1}' | head -1)

prompt REPO_URL    "Git repo URL" "$REPO_URL"
prompt TARGET_DISK "Target disk device" "${DETECTED_DISK:-}"
prompt_secret LUKS_PASSPHRASE "LUKS passphrase"

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
    DETECTED_KEY_DEV=$(lsblk -d -o NAME,RM,TYPE --noheadings | awk '$2=="1" && $3=="disk" {print "/dev/"$1"1"}' | head -1)
    prompt KEY_DEVICE "Key USB partition" "${DETECTED_KEY_DEV:-}"
    ;;
  2)
    echo
    prompt KEY_FILE_PATH "Absolute path to the key file" "/run/media/nixos/keys/$KEY_FILENAME"
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

# -- step 1: secure the live session ------------------------------------------

echo
echo "=== Securing live session ==="
passwd nixos

# -- step 2: clone the repo to tmp ---------------------------------------------

echo
echo "=== Cloning repo to live RAM ==="
if [[ -e "$REPO_TMP" ]]; then
  sudo rm -rf "$REPO_TMP"
fi
nix-shell -p git --run "git clone '$REPO_URL' '$REPO_TMP'"

echo
echo "=== Select target host ==="
mapfile -t AVAILABLE_HOSTS < <(find "$REPO_TMP/hosts" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)

if [[ ${#AVAILABLE_HOSTS[@]} -eq 0 ]]; then
  echo "Error: no hosts found in $REPO_TMP/hosts." >&2
  exit 1
fi

echo "Available hosts:"
for i in "${!AVAILABLE_HOSTS[@]}"; do
  echo "  $((i+1))) ${AVAILABLE_HOSTS[$i]}"
done
echo

while true; do
  # 1. Update the prompt string to explicitly show [1] as the default
  read -rp "Select host [1-${#AVAILABLE_HOSTS[@]}] [1]: " host_choice
  
  # 2. If the user just hits Enter, force host_choice to "1"
  if [[ -z "$host_choice" ]]; then
    host_choice="1"
  fi

  if [[ "$host_choice" =~ ^[0-9]+$ ]] && (( host_choice >= 1 && host_choice <= ${#AVAILABLE_HOSTS[@]} )); then
    FLAKE_TARGET="${AVAILABLE_HOSTS[$((host_choice-1))]}"
    break
  fi
  echo "Invalid selection. Enter a number between 1 and ${#AVAILABLE_HOSTS[@]}."
done

echo "Installing host: $FLAKE_TARGET"

# -- step 4: provision disks ---------------------------------------------------

echo
echo "=== Provisioning disks ==="
PASSPHRASE_FILE="/tmp/encryption-password"
touch "$PASSPHRASE_FILE"
chmod 600 "$PASSPHRASE_FILE"
printf '%s' "$LUKS_PASSPHRASE" > "$PASSPHRASE_FILE"
unset LUKS_PASSPHRASE

sudo NIX_CONFIG="$NIX_CONFIG" nix run github:nix-community/disko -- \
  --mode destroy,format,mount \
  "$REPO_TMP/hosts/$FLAKE_TARGET/disko.nix"

sudo shred -vfzu "$PASSPHRASE_FILE"

# -- step 5: prepare target directory and move repo ---------------------------

echo
echo "=== Moving repo to newly mounted target ==="
sudo mkdir -p -m 0700 /mnt/etc/nixos
sudo cp -r "$REPO_TMP" "$REPO_TARGET"
sudo chown -R nixos:users "$REPO_TARGET"

# -- step 6: install age identity ---------------------------------------------

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

# -- step 6.5: prepare lanzaboote secure boot keys ----------------------------

echo
echo "=== Initializing Lanzaboote Secure Boot Keys ==="
# 1. Create the persistent target directory on the SSD
sudo mkdir -p -m 0700 /mnt/etc/secureboot

# 2. Create the temporary directory the live image expects
sudo mkdir -p -m 0700 /var/lib/sbctl

# 3. Bind mount the SSD directory to the live image path
sudo mount --bind /mnt/etc/secureboot /var/lib/sbctl

# 4. Run sbctl completely naturally. It writes to /var/lib/sbctl, 
# but the data physically lands on your SSD inside /mnt/etc/secureboot/keys
sudo NIX_CONFIG="$NIX_CONFIG" nix run nixpkgs#sbctl -- create-keys

# 5. Clean up the bind mount
sudo umount /var/lib/sbctl

# 6. FORCE INITIALIZE SYSTEMD-BOOT FOR LANZABOOTE (The missing piece)
echo "=== Pre-seeding systemd-boot files ==="
sudo bootctl --esp-path=/mnt/boot --boot-path=/mnt/boot install

# -- step 7: install -----------------------------------------------------------

echo
echo "=== Running nixos-install ==="
sudo NIX_CONFIG="$NIX_CONFIG" nixos-install --flake "$REPO_TARGET#$FLAKE_TARGET"

echo
echo "=== Install complete. Remove USB drives and reboot. ==="
