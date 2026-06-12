#!/usr/bin/env python3
"""
enroll.py

Enrolls a new machine in the NixOS config:
  1. Adds the machine's age identity to secrets/secrets.nix
  2. Generates and encrypts an SSH keypair as an agenix secret
  3. Creates hosts/<machine>/secrets.nix and wires it into configuration.nix
  4. Updates lib/ssh-hosts.nix with the machine entry
  5. Re-keys all secrets so the new machine can decrypt them

Prerequisites: git, age, age-keygen, ssh-keygen, shred, nix are in PATH.
If age is missing: nix develop -c python3 tools/enroll.py <machine>
"""

import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from common import die, prompt, repo_root, run


def _require_cmds(machine_name: str) -> None:
    missing = []
    for cmd in ("age", "age-keygen", "ssh-keygen", "shred", "nix", "git"):
        result = subprocess.run(
            ["command", "-v", cmd], shell=False,
            capture_output=True,
        )
        # Use 'which' as fallback since 'command -v' needs a shell
        r2 = subprocess.run(["which", cmd], capture_output=True)
        if r2.returncode != 0:
            missing.append(cmd)
    if missing:
        die(
            f"Missing commands: {', '.join(missing)}. "
            f"Run via: nix develop -c python3 tools/enroll.py {machine_name}"
        )


def _get_offline_admin_pub(secrets_nix: Path) -> str:
    content = secrets_nix.read_text()
    m = re.search(r'offlineAdmin = "([^"]+)"', content)
    if not m:
        die(f"Could not find offlineAdmin key in {secrets_nix}")
    return m.group(1)


def _get_existing_age_key(secrets_nix: Path, machine_name: str) -> str | None:
    content = secrets_nix.read_text()
    m = re.search(rf'^\s+{re.escape(machine_name)}\s*=\s*"(age1[^"]+)"', content, re.MULTILINE)
    if m:
        return m.group(1)
    return None


def enroll_machine(machine: str, username: str = "thomasga") -> bool:
    """
    Enroll a machine. Returns True if enrollment succeeded or was already done.
    """
    root = repo_root()
    if root is None:
        die("Not inside a git repo. Run from inside the nixos-config repo.")

    host_dir = root / "hosts" / machine
    if not host_dir.is_dir():
        die(f"No host directory at hosts/{machine}")

    secrets_nix = root / "secrets" / "secrets.nix"
    ssh_hosts_nix = root / "lib" / "ssh-hosts.nix"
    host_secrets_nix = host_dir / "secrets.nix"
    host_config_nix = host_dir / "configuration.nix"
    ssh_secret_path = f"secrets/thomasga/ssh-id-ed25519-{machine}.age"
    ssh_age_file = root / ssh_secret_path

    print(f"=== Enrolling machine: {machine} (user: {username}) ===")
    print()

    # ── step 1: age identity ──────────────────────────────────────────────────

    print("--- Age identity ---")
    print()

    offline_admin_pub = _get_offline_admin_pub(secrets_nix)
    age_public_key = _get_existing_age_key(secrets_nix, machine)
    age_choice = None

    if age_public_key:
        print(f"Machine '{machine}' already has an age identity: {age_public_key}")
        print()
    else:
        print("Age identity key source:")
        print("  1) I have the age public key (machine already booted and ran age-keygen)")
        print("  2) Generate a new keypair here (pre-provisioning before first boot)")
        print("  3) Skip (add manually to secrets/secrets.nix later)")
        print()
        age_choice = input("Choice [1/2/3]: ").strip()

        if age_choice == "1":
            print()
            print(f"Paste the age public key for '{machine}' (age1...):")
            age_public_key = prompt("Age public key")
            if not age_public_key.startswith("age1"):
                die("Age public key must start with 'age1'")

        elif age_choice == "2":
            key_dir = Path.home() / ".config" / "agenix"
            key_dir.mkdir(parents=True, exist_ok=True)
            key_dir.chmod(0o700)
            identity_file = key_dir / f"{machine}.age"

            if identity_file.exists():
                print(f"Existing identity found at {identity_file}")
                content = identity_file.read_text()
                m = re.search(r"^# public key: (.+)$", content, re.MULTILINE)
                if m:
                    age_public_key = m.group(1).strip()
                else:
                    die(f"Could not parse public key from {identity_file}")
                print(f"Public key: {age_public_key}")
            else:
                print("Generating age keypair...")
                result = run(
                    ["age-keygen", "-o", str(identity_file)],
                    capture_output=True,
                    text=True,
                )
                identity_file.chmod(0o400)
                # age-keygen prints "Public key: age1..." to stderr
                output = result.stderr + result.stdout
                m = re.search(r"Public key: (age1\S+)", output)
                if not m:
                    die("Could not parse public key from age-keygen output")
                age_public_key = m.group(1)
                print(f"Private key: {identity_file}")
                print(f"Public key:  {age_public_key}")
                print()
                print("  Install to the new machine before first boot:")
                print(f"  → WSL: tools\\install.py will prompt for this file")
                print(f"  → Physical: sudo python3 tools/install_age_identity.py --file {identity_file}")

        elif age_choice == "3":
            print("Skipping age identity. Add it to secrets/secrets.nix manually.")
            age_public_key = None
        else:
            die("Invalid choice")

        print()

        if age_public_key:
            content = secrets_nix.read_text()
            placeholder = f"  # {machine} = "
            if placeholder in content:
                content = re.sub(
                    rf"^  # {re.escape(machine)} = .*$",
                    f'  {machine} = "{age_public_key}";',
                    content,
                    flags=re.MULTILINE,
                )
                secrets_nix.write_text(content)
                print(f"Updated secrets/secrets.nix: replaced placeholder comment for {machine}")
            else:
                content = re.sub(
                    r"^  offlineAdmin = ",
                    f'  {machine} = "{age_public_key}";\n\n  offlineAdmin = ',
                    content,
                    flags=re.MULTILINE,
                )
                secrets_nix.write_text(content)
                print(f"Updated secrets/secrets.nix: added {machine} binding")

    print()

    # ── step 2: ssh keypair ───────────────────────────────────────────────────

    print("--- SSH keypair ---")
    print()

    ssh_pub_key = ""

    if ssh_age_file.exists():
        print(f"SSH secret already exists at {ssh_secret_path} — skipping key generation.")
        print()
    else:
        print(f"Generate an SSH ed25519 keypair for {username}@{machine}?")
        print(f"  The private key is encrypted with age and stored in {ssh_secret_path}.")
        print("  The plaintext key is shredded immediately after encryption.")
        print()
        gen_ssh = input("Generate SSH keypair? [Y/n]: ").strip() or "y"

        if gen_ssh.lower() == "y":
            if not age_public_key:
                die(
                    f"Cannot encrypt SSH key: no age identity for {machine}. "
                    "Re-run after adding age identity."
                )

            with tempfile.TemporaryDirectory() as tmp_dir:
                tmp_key = Path(tmp_dir) / "id_ed25519"
                print("Generating SSH keypair...")
                run([
                    "ssh-keygen", "-t", "ed25519",
                    "-C", f"{username}@{machine}",
                    "-N", "", "-f", str(tmp_key), "-q",
                ])
                ssh_pub_key = (tmp_key.with_suffix(".pub")).read_text().strip()
                print(f"Public key: {ssh_pub_key}")
                print()

                ssh_age_file.parent.mkdir(parents=True, exist_ok=True)

                print("Encrypting private key...")
                with open(tmp_key, "rb") as key_in:
                    run([
                        "age",
                        "-r", age_public_key,
                        "-r", offline_admin_pub,
                        "-o", str(ssh_age_file),
                    ], stdin=key_in)

                run(["shred", "-fzu", str(tmp_key)])

            print(f"Encrypted: {ssh_secret_path}")
            print()
        else:
            print("Skipped.")
            print()

    # ── step 3: hosts/<machine>/secrets.nix ──────────────────────────────────

    print("--- Host secrets file ---")
    print()

    if not host_secrets_nix.exists():
        host_secrets_nix.write_text(
            f"{{...}}: {{\n"
            f"  age.secrets = {{\n"
            f'    "thomasga/ssh-id-ed25519-{machine}" = {{\n'
            f"      file = ../../{ssh_secret_path};\n"
            f'      owner = "{username}";\n'
            f"    }};\n"
            f"    # Add further machine-specific secrets here (NAS, restic, etc.)\n"
            f"  }};\n"
            f"}}\n"
        )
        print(f"Created hosts/{machine}/secrets.nix")
        print()
    else:
        print(f"hosts/{machine}/secrets.nix already exists — not overwriting.")
        print()

    # Add ./secrets.nix import to configuration.nix if missing
    if host_config_nix.exists():
        config_content = host_config_nix.read_text()
        if r"./secrets.nix" in config_content or "./secrets.nix" in config_content:
            print(f"hosts/{machine}/configuration.nix already imports secrets.nix")
        else:
            config_content = re.sub(
                r"^(  imports = \[)$",
                r"\1\n    ./secrets.nix",
                config_content,
                flags=re.MULTILINE,
            )
            host_config_nix.write_text(config_content)
            print(f"Added ./secrets.nix import to hosts/{machine}/configuration.nix")
    print()

    # ── step 4: secrets/secrets.nix — ssh secret entry ───────────────────────

    print("--- SSH secret entry in secrets/secrets.nix ---")
    print()

    ssh_secret_key = f"thomasga/ssh-id-ed25519-{machine}.age"
    secrets_content = secrets_nix.read_text()

    if f'"{ssh_secret_key}"' in secrets_content:
        print(f"Entry already present: {ssh_secret_key}")
    else:
        if age_public_key:
            secrets_content = re.sub(
                r"^}$",
                f'  "{ssh_secret_key}".publicKeys = [{machine} offlineAdmin];\n}}',
                secrets_content,
                flags=re.MULTILINE,
            )
            secrets_nix.write_text(secrets_content)
            print(f"Added {ssh_secret_key} to secrets/secrets.nix")
        else:
            print("Skipped (no age identity — add manually when identity is known).")
            print("  Add to secrets/secrets.nix:")
            print(f'    "{ssh_secret_key}".publicKeys = [{machine} offlineAdmin];')
    print()

    # ── step 5: lib/ssh-hosts.nix ────────────────────────────────────────────

    print("--- lib/ssh-hosts.nix ---")
    print()

    ssh_hosts_content = ssh_hosts_nix.read_text()

    if f"  {machine} = {{" in ssh_hosts_content:
        print(f"Entry for {machine} already exists in lib/ssh-hosts.nix")
        if ssh_pub_key:
            print("  Update the userPublicKey field manually:")
            print(f'    userPublicKey = "{ssh_pub_key}";')
    else:
        user_pub_key_expr = f'"{ssh_pub_key}"' if ssh_pub_key else "null"
        new_entry = (
            f'  {machine} = {{\n'
            f'    aliases = ["{machine}"];\n'
            f'    hostName = "{machine}";\n'
            f'    publicKey = null;\n'
            f'    user = "{username}";\n'
            f'    userPublicKey = {user_pub_key_expr};\n'
            f'  }};'
        )
        ssh_hosts_content = re.sub(
            r"^}$",
            f"{new_entry}\n}}",
            ssh_hosts_content,
            flags=re.MULTILINE,
        )
        ssh_hosts_nix.write_text(ssh_hosts_content)
        print(f"Added {machine} to lib/ssh-hosts.nix")
        print("  publicKey is null — update after collecting the SSH host key:")
        print(f"    ssh-keyscan -t ed25519 {machine}")
    print()

    # ── step 6: rekey ─────────────────────────────────────────────────────────

    print("--- Re-keying secrets ---")
    print()

    if age_public_key:
        run(["nix", "run", ".#secret-rekey"], cwd=str(root))
        print()
        print("Rekey complete.")
    else:
        print("Skipped (no age identity added). Run 'nix run .#secret-rekey' after adding the identity.")
    print()

    # ── next steps ────────────────────────────────────────────────────────────

    print(f"=== Enrollment complete: {machine} ===")
    print()
    print("Next steps:")
    print()
    print("  1. Commit the changes:")
    print(f"     git add secrets/ lib/ssh-hosts.nix hosts/{machine}/ roles/common/")
    print(f"     git commit -m 'feat: enroll {machine}'")
    print()
    if age_choice == "2":
        print("  2. Install the age identity on the new machine before first boot:")
        print(f"     → WSL: run  python tools\\\\install.py  on Windows, select {machine}, provide this file")
        print(f"     → Physical: sudo python3 tools/install_age_identity.py --file ~/.config/agenix/{machine}.age")
        print()
    print("  3. After first boot, collect the SSH host key and pin it:")
    print(f"     ssh-keyscan -t ed25519 {machine}")
    print("     # Paste the key into lib/ssh-hosts.nix as publicKey = \"...\"")
    print()
    print("  4. After pinning the host key, rebuild to activate known_hosts:")
    disko_path = host_dir / "disko.nix"
    if disko_path.exists():
        print(f"     sudo nixos-rebuild switch --flake .#{machine}")
    else:
        print(f"     sudo nixos-rebuild switch --flake .#{machine}  # run inside the WSL distro")

    return True


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Enroll a new machine in the NixOS config.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  python3 tools/enroll.py holodeck-01\n"
            "  python3 tools/enroll.py holodeck-02 --user thomasga\n\n"
            "Requires: git, age, age-keygen, ssh-keygen, shred.\n"
            "If age is not in PATH:  nix develop -c python3 tools/enroll.py <machine>"
        ),
    )
    parser.add_argument("machine", help="Machine name (must match hosts/<machine>/ directory)")
    parser.add_argument("--user", default="thomasga", help="NixOS user (default: thomasga)")
    args = parser.parse_args()

    enroll_machine(args.machine, username=args.user)


if __name__ == "__main__":
    main()
