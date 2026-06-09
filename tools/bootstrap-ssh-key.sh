#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF' >&2
Usage: bash tools/bootstrap-ssh-key.sh <host-name> [--output-dir <dir>]

Generates a per-host ed25519 SSH keypair under ~/.ssh by default, then helps
you encrypt it as an agenix secret so it can be deployed consistently across machines.
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

host_name=
output_dir="$HOME/.ssh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      output_dir="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$host_name" ]]; then
        host_name="$1"
        shift
      else
        echo "Unknown argument: $1" >&2
        usage
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$host_name" ]]; then
  usage
  exit 1
fi

mkdir -p "$output_dir"
chmod 700 "$output_dir"

key_path="$output_dir/id_ed25519"

if [[ -e "$key_path" || -e "$key_path.pub" ]]; then
  echo "Refusing to overwrite existing key material at $key_path" >&2
  exit 1
fi

ssh-keygen -t ed25519 -f "$key_path" -C "$USER@$host_name" -N ""

echo
echo "Generated keypair:"
echo "  Private: $key_path"
echo "  Public:  $key_path.pub"
echo

# Offer to encrypt the private key as an agenix secret
read -p "Encrypt this private key as an agenix secret? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  secret_path="$repo_root/secrets/thomasga/ssh-id-ed25519-${host_name}.age"

  echo
  echo "To encrypt: EDITOR=nano nix run .#secret-edit -- secrets/thomasga/ssh-id-ed25519-${host_name}.age"
  echo "Then paste the contents of: $key_path"
  echo
  echo "After encryption is complete, securely delete the unencrypted key:"
  echo "  shred -vfz $key_path"
  echo
  echo "After that, add to secrets/secrets.nix:"
  echo "  \"thomasga/ssh-id-ed25519-${host_name}.age\".publicKeys = [${host_name} offlineAdmin];"
  echo
fi

echo
echo "Public key to distribute to managed hosts:"
cat "$key_path.pub"
echo
echo "Collect and verify the SSH host key before pinning it in lib/ssh-hosts.nix:"
echo "  ssh-keyscan -t ed25519 $host_name"
