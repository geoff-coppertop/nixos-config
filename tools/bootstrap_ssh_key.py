#!/usr/bin/env python3
"""
bootstrap_ssh_key.py

Generates a per-host ed25519 SSH keypair under ~/.ssh by default, then helps
you encrypt it as an agenix secret so it can be deployed consistently across machines.
"""

import argparse
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from common import die, repo_root, run


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Generate a per-host ed25519 SSH keypair and optionally encrypt it "
            "as an agenix secret."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        usage="python3 tools/bootstrap_ssh_key.py <host-name> [--output-dir <dir>]",
    )
    parser.add_argument("host_name", help="Host name for the keypair comment")
    parser.add_argument(
        "--output-dir",
        default=str(Path.home() / ".ssh"),
        help="Directory to write the keypair (default: ~/.ssh)",
    )
    args = parser.parse_args()

    host_name = args.host_name
    output_dir = Path(args.output_dir)

    output_dir.mkdir(parents=True, exist_ok=True)
    output_dir.chmod(0o700)

    key_path = output_dir / "id_ed25519"

    if key_path.exists() or key_path.with_suffix(".pub").exists():
        print(f"Refusing to overwrite existing key material at {key_path}", file=sys.stderr)
        sys.exit(1)

    user = os.environ.get("USER", os.environ.get("LOGNAME", "user"))
    run([
        "ssh-keygen", "-t", "ed25519",
        "-f", str(key_path),
        "-C", f"{user}@{host_name}",
        "-N", "",
    ])

    print()
    print("Generated keypair:")
    print(f"  Private: {key_path}")
    print(f"  Public:  {key_path}.pub")
    print()

    reply = input("Encrypt this private key as an agenix secret? (y/n) ").strip().lower()
    print()
    if reply == "y":
        root = repo_root()
        secret_rel = f"secrets/thomasga/ssh-id-ed25519-{host_name}.age"
        print(f"To encrypt: EDITOR=nano nix run .#secret-edit -- {secret_rel}")
        print(f"Then paste the contents of: {key_path}")
        print()
        print("After encryption is complete, securely delete the unencrypted key:")
        print(f"  shred -vfz {key_path}")
        print()
        print("After that, add to secrets/secrets.nix:")
        print(f'  "thomasga/ssh-id-ed25519-{host_name}.age".publicKeys = [{host_name} offlineAdmin];')
        print()

    print()
    print("Public key to distribute to managed hosts:")
    pub_key = key_path.with_suffix(".pub").read_text().strip()
    print(pub_key)
    print()
    print("Collect and verify the SSH host key before pinning it in lib/ssh-hosts.nix:")
    print(f"  ssh-keyscan -t ed25519 {host_name}")


if __name__ == "__main__":
    main()
