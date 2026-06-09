#!/usr/bin/env bash
# enroll-machine.sh
#
# Enrolls a new machine in the NixOS config:
#   1. Adds the machine's age identity to secrets/secrets.nix
#   2. Generates and encrypts an SSH keypair as an agenix secret
#   3. Creates hosts/<machine>/secrets.nix and wires it into configuration.nix
#   4. Updates lib/ssh-hosts.nix with the machine entry
#   5. Re-keys all secrets so the new machine can decrypt them
#
# Prerequisites: git, age, ssh-keygen, shred are in PATH.
# If age is missing: nix develop -c bash tools/enroll-machine.sh <machine>
#
# Run from anywhere inside the repo.

set -euo pipefail

# ── helpers ──────────────────────────────────────────────────────────────────

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

usage() {
  cat <<'EOF' >&2
Usage: bash tools/enroll-machine.sh <machine-name> [--user <username>]

Options:
  --user <username>   NixOS user whose SSH key is enrolled (default: thomasga)
  -h, --help          Show this help

Examples:
  bash tools/enroll-machine.sh holodeck-01
  bash tools/enroll-machine.sh holodeck-02 --user thomasga

Requires: git, age, ssh-keygen, shred.
If age is not in PATH:  nix develop -c bash tools/enroll-machine.sh <machine>
EOF
}

die() { echo "Error: $*" >&2; exit 1; }

require_cmd() {
  for cmd in "$@"; do
    command -v "$cmd" &>/dev/null \
      || die "'$cmd' not found. Run via: nix develop -c bash tools/enroll-machine.sh $MACHINE_NAME"
  done
}

prompt() {
  local var_name="$1" message="$2" default="${3:-}" value
  if [[ -n "$default" ]]; then
    read -rp "$message [$default]: " value
    value="${value:-$default}"
  else
    read -rp "$message: " value
  fi
  [[ -n "$value" ]] || die "value required"
  printf -v "$var_name" '%s' "$value"
}

# ── argument parsing ──────────────────────────────────────────────────────────

MACHINE_NAME=""
USERNAME="thomasga"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)   USERNAME="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*)       die "Unknown option: $1" ;;
    *)
      if [[ -z "$MACHINE_NAME" ]]; then
        MACHINE_NAME="$1"; shift
      else
        die "Unexpected argument: $1"
      fi
      ;;
  esac
done

[[ -n "$MACHINE_NAME" ]] || { usage; exit 1; }

require_cmd age age-keygen ssh-keygen shred nix git

# ── validate machine ──────────────────────────────────────────────────────────

HOST_DIR="$REPO_ROOT/hosts/$MACHINE_NAME"
[[ -d "$HOST_DIR" ]] || die "No host directory at hosts/$MACHINE_NAME"

SECRETS_NIX="$REPO_ROOT/secrets/secrets.nix"
SSH_HOSTS_NIX="$REPO_ROOT/lib/ssh-hosts.nix"
HOST_SECRETS_NIX="$HOST_DIR/secrets.nix"
HOST_CONFIG_NIX="$HOST_DIR/configuration.nix"
SSH_SECRET_PATH="secrets/thomasga/ssh-id-ed25519-${MACHINE_NAME}.age"

echo "=== Enrolling machine: $MACHINE_NAME (user: $USERNAME) ==="
echo

# ── step 1: age identity ──────────────────────────────────────────────────────

echo "--- Age identity ---"
echo

OFFLINE_ADMIN_PUB=$(
  grep 'offlineAdmin = "' "$SECRETS_NIX" \
    | sed 's/.*= "\(.*\)".*/\1/'
)

# Check if already enrolled
if grep -q "^  ${MACHINE_NAME} = \"age1" "$SECRETS_NIX" 2>/dev/null; then
  AGE_PUBLIC_KEY=$(
    grep "^  ${MACHINE_NAME} = \"age1" "$SECRETS_NIX" \
      | sed 's/.*= "\(.*\)".*/\1/'
  )
  echo "Machine '$MACHINE_NAME' already has an age identity: $AGE_PUBLIC_KEY"
  echo
else
  echo "Age identity key source:"
  echo "  1) I have the age public key (machine already booted and ran age-keygen)"
  echo "  2) Generate a new keypair here (pre-provisioning before first boot)"
  echo "  3) Skip (add manually to secrets/secrets.nix later)"
  echo
  read -rp "Choice [1/2/3]: " age_choice

  case "$age_choice" in
    1)
      echo
      echo "Paste the age public key for '$MACHINE_NAME' (age1...):"
      prompt AGE_PUBLIC_KEY "Age public key"
      if [[ "$AGE_PUBLIC_KEY" != age1* ]]; then
        die "Age public key must start with 'age1'"
      fi
      ;;
    2)
      KEY_DIR="$HOME/.config/agenix"
      mkdir -p "$KEY_DIR"
      chmod 700 "$KEY_DIR"
      IDENTITY_FILE="$KEY_DIR/${MACHINE_NAME}.age"

      if [[ -f "$IDENTITY_FILE" ]]; then
        echo "Existing identity found at $IDENTITY_FILE"
        AGE_PUBLIC_KEY=$(grep '^# public key:' "$IDENTITY_FILE" | sed 's/.*: //')
        echo "Public key: $AGE_PUBLIC_KEY"
      else
        echo "Generating age keypair..."
        AGE_PUBLIC_KEY=$(age-keygen -o "$IDENTITY_FILE" 2>&1 | grep '^Public key:' | sed 's/Public key: //')
        chmod 400 "$IDENTITY_FILE"
        echo "Private key: $IDENTITY_FILE"
        echo "Public key:  $AGE_PUBLIC_KEY"
        echo
        echo "  Install to the new machine before first boot:"
        echo "  → WSL: tools/install-wsl.ps1 will pick up ~/.config/agenix/${MACHINE_NAME}.age"
        echo "  → Physical: sudo bash tools/install-age-identity.sh --file $IDENTITY_FILE"
      fi
      ;;
    3)
      echo "Skipping age identity. Add it to secrets/secrets.nix manually."
      AGE_PUBLIC_KEY=""
      ;;
    *)
      die "Invalid choice" ;;
  esac

  echo

  if [[ -n "$AGE_PUBLIC_KEY" ]]; then
    # Replace placeholder comment or insert before offlineAdmin
    if grep -q "^  # ${MACHINE_NAME} = " "$SECRETS_NIX"; then
      sed -i "s|^  # ${MACHINE_NAME} = .*|  ${MACHINE_NAME} = \"${AGE_PUBLIC_KEY}\";|" "$SECRETS_NIX"
      echo "Updated secrets/secrets.nix: replaced placeholder comment for $MACHINE_NAME"
    else
      sed -i "s|^  offlineAdmin = |  ${MACHINE_NAME} = \"${AGE_PUBLIC_KEY}\";\n\n  offlineAdmin = |" "$SECRETS_NIX"
      echo "Updated secrets/secrets.nix: added $MACHINE_NAME binding"
    fi
  fi
fi

echo

# ── step 2: ssh keypair ───────────────────────────────────────────────────────

echo "--- SSH keypair ---"
echo

SSH_AGE_FILE="$REPO_ROOT/$SSH_SECRET_PATH"

if [[ -f "$SSH_AGE_FILE" ]]; then
  echo "SSH secret already exists at $SSH_SECRET_PATH — skipping key generation."
  echo
  SSH_PUB_KEY=""
else
  echo "Generate an SSH ed25519 keypair for $USERNAME@$MACHINE_NAME?"
  echo "  The private key is encrypted with age and stored in $SSH_SECRET_PATH."
  echo "  The plaintext key is shredded immediately after encryption."
  echo
  read -rp "Generate SSH keypair? [Y/n]: " gen_ssh
  gen_ssh="${gen_ssh:-y}"

  if [[ "$gen_ssh" =~ ^[Yy]$ ]]; then
    if [[ -z "$AGE_PUBLIC_KEY" ]]; then
      die "Cannot encrypt SSH key: no age identity for $MACHINE_NAME. Re-run after adding age identity."
    fi

    TMP_SSH_DIR=$(mktemp -d)
    TMP_SSH_KEY="$TMP_SSH_DIR/id_ed25519"
    trap 'shred -fzu "$TMP_SSH_KEY" 2>/dev/null; rm -rf "$TMP_SSH_DIR"' EXIT

    echo "Generating SSH keypair..."
    ssh-keygen -t ed25519 -C "${USERNAME}@${MACHINE_NAME}" -N "" -f "$TMP_SSH_KEY" -q

    SSH_PUB_KEY=$(cat "$TMP_SSH_KEY.pub")
    echo "Public key: $SSH_PUB_KEY"
    echo

    mkdir -p "$(dirname "$SSH_AGE_FILE")"

    echo "Encrypting private key..."
    age \
      -r "$AGE_PUBLIC_KEY" \
      -r "$OFFLINE_ADMIN_PUB" \
      -o "$SSH_AGE_FILE" \
      < "$TMP_SSH_KEY"

    shred -fzu "$TMP_SSH_KEY"
    rm -rf "$TMP_SSH_DIR"
    trap - EXIT

    echo "Encrypted: $SSH_SECRET_PATH"
    echo
  else
    SSH_PUB_KEY=""
    echo "Skipped."
    echo
  fi
fi

# ── step 3: hosts/<machine>/secrets.nix ──────────────────────────────────────

echo "--- Host secrets file ---"
echo

if [[ ! -f "$HOST_SECRETS_NIX" ]]; then
  cat > "$HOST_SECRETS_NIX" <<NIXEOF
{...}: {
  age.secrets = {
    "thomasga/ssh-id-ed25519-${MACHINE_NAME}" = {
      file = ../../${SSH_SECRET_PATH};
      owner = "${USERNAME}";
    };
    # Add further machine-specific secrets here (NAS, restic, etc.)
  };
}
NIXEOF
  echo "Created hosts/$MACHINE_NAME/secrets.nix"
  echo
else
  echo "hosts/$MACHINE_NAME/secrets.nix already exists — not overwriting."
  echo
fi

# Add ./secrets.nix import to configuration.nix if missing
if grep -q '\.\/secrets\.nix' "$HOST_CONFIG_NIX" 2>/dev/null; then
  echo "hosts/$MACHINE_NAME/configuration.nix already imports secrets.nix"
else
  # Insert ./secrets.nix as the first import
  sed -i 's|^\(  imports = \[\)$|\1\n    ./secrets.nix|' "$HOST_CONFIG_NIX"
  echo "Added ./secrets.nix import to hosts/$MACHINE_NAME/configuration.nix"
fi
echo

# ── step 4: secrets/secrets.nix — ssh secret entry ───────────────────────────

echo "--- SSH secret entry in secrets/secrets.nix ---"
echo

SSH_SECRET_KEY="thomasga/ssh-id-ed25519-${MACHINE_NAME}.age"

if grep -q "\"${SSH_SECRET_KEY}\"" "$SECRETS_NIX"; then
  echo "Entry already present: $SSH_SECRET_KEY"
else
  if [[ -n "$AGE_PUBLIC_KEY" ]]; then
    # Insert before the closing }
    sed -i "s|^}$|  \"${SSH_SECRET_KEY}\".publicKeys = [${MACHINE_NAME} offlineAdmin];\n}|" "$SECRETS_NIX"
    echo "Added $SSH_SECRET_KEY to secrets/secrets.nix"
  else
    echo "Skipped (no age identity — add manually when identity is known)."
    echo "  Add to secrets/secrets.nix:"
    echo "    \"${SSH_SECRET_KEY}\".publicKeys = [${MACHINE_NAME} offlineAdmin];"
  fi
fi
echo

# ── step 5: lib/ssh-hosts.nix ────────────────────────────────────────────────

echo "--- lib/ssh-hosts.nix ---"
echo

if grep -q "  ${MACHINE_NAME} = {" "$SSH_HOSTS_NIX"; then
  echo "Entry for $MACHINE_NAME already exists in lib/ssh-hosts.nix"
  if [[ -n "$SSH_PUB_KEY" ]]; then
    echo "  Update the userPublicKey field manually:"
    echo "    userPublicKey = \"$SSH_PUB_KEY\";"
  fi
else
  USER_PUB_KEY_EXPR="null"
  if [[ -n "${SSH_PUB_KEY:-}" ]]; then
    USER_PUB_KEY_EXPR="\"$SSH_PUB_KEY\""
  fi

  # Insert the new entry before the closing }
  NEW_ENTRY="  ${MACHINE_NAME} = {\n    aliases = [\"${MACHINE_NAME}\"];\n    hostName = \"${MACHINE_NAME}\";\n    publicKey = null;\n    user = \"${USERNAME}\";\n    userPublicKey = ${USER_PUB_KEY_EXPR};\n  };"
  sed -i "s|^}$|${NEW_ENTRY}\n}|" "$SSH_HOSTS_NIX"
  echo "Added $MACHINE_NAME to lib/ssh-hosts.nix"
  echo "  publicKey is null — update after collecting the SSH host key:"
  echo "    ssh-keyscan -t ed25519 $MACHINE_NAME"
fi
echo

# ── step 6: rekey ─────────────────────────────────────────────────────────────

echo "--- Re-keying secrets ---"
echo

if [[ -n "$AGE_PUBLIC_KEY" ]]; then
  cd "$REPO_ROOT"
  nix run .#secret-rekey
  echo
  echo "Rekey complete."
else
  echo "Skipped (no age identity added). Run 'nix run .#secret-rekey' after adding the identity."
fi
echo

# ── next steps ────────────────────────────────────────────────────────────────

echo "=== Enrollment complete: $MACHINE_NAME ==="
echo
echo "Next steps:"
echo
echo "  1. Commit the changes:"
echo "     git add secrets/ lib/ssh-hosts.nix hosts/$MACHINE_NAME/ roles/common/"
echo "     git commit -m 'feat: enroll $MACHINE_NAME'"
echo
if [[ "${age_choice:-}" == "2" ]]; then
  echo "  2. Install the age identity on the new machine before first boot:"
  echo "     → WSL: tools/install-wsl.ps1 picks up ~/.config/agenix/${MACHINE_NAME}.age automatically"
  echo "     → Physical: sudo bash tools/install-age-identity.sh --file ~/.config/agenix/${MACHINE_NAME}.age"
  echo
fi
echo "  3. After first boot, collect the SSH host key and pin it:"
echo "     ssh-keyscan -t ed25519 $MACHINE_NAME"
echo "     # Paste the key into lib/ssh-hosts.nix as publicKey = \"...\""
echo
echo "  4. After pinning the host key, rebuild to activate known_hosts:"
if [[ -f "$HOST_DIR/disko.nix" ]]; then
  echo "     sudo nixos-rebuild switch --flake .#$MACHINE_NAME"
else
  echo "     sudo nixos-rebuild switch --flake .#$MACHINE_NAME  # run inside the WSL distro"
fi
