# SSH Keys And Host Trust

SSH trust is managed separately from agenix secrets.

- SSH login keys are per-host keypairs, stored as agenix secrets.
- SSH host trust is pinned in `lib/ssh-hosts.nix` and rendered to
  `programs.ssh.knownHosts` by `modules/ssh-known-hosts.nix`.
- `known_hosts` records **server identity**. `authorized_keys` grants **login
  access**. They are different data flows and are wired separately.

## The Inventory: `lib/ssh-hosts.nix`

`lib/ssh-hosts.nix` is the single inventory for all managed machines. Each entry
has:

| Field | Meaning |
| --- | --- |
| `hostName` | The real SSH hostname |
| `aliases` | Optional short names to expose in SSH config |
| `publicKey` | The verified SSH **host** public key (server identity); `null` until pinned |
| `user` | The default SSH username |
| `userPublicKeys` | Attrset of `<username> = "<login public key>"` enrolled on that machine; `{}` until enrolled |

```nix
enterprise-d = {
  aliases = ["enterprise-d"];
  hostName = "enterprise-d";
  publicKey = null;
  user = "thomasga";
  userPublicKeys = {
    thomasga = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... thomasga@enterprise-d";
  };
};
```

Two consumers read it:

- `modules/ssh-known-hosts.nix` turns non-null `publicKey` values into
  `programs.ssh.knownHosts`, so clients do not prompt on first connect.
- `roles/common/users.nix` collects, for each user, every `userPublicKeys.<user>`
  entry across all machines into that user's `openssh.authorizedKeys.keys`. Once
  a user is enrolled on a machine, they can log in from it to every other machine
  that declares them.

No machine currently has `publicKey` pinned — all three are `null`, pending the
out-of-band verification below.

## Generate SSH Login Credentials

`tools/enroll.py` generates a per-machine SSH keypair, encrypts it as an agenix
secret, and wires everything up:

```bash
nix develop -c python3 tools/enroll.py <machine-name>
```

The script:

1. Adds the machine's age identity to `secrets/secrets.nix` (generated, or one
   you provide)
2. Generates an ed25519 SSH keypair, encrypts the private key with `age`, and
   shreds the plaintext
3. Creates `hosts/<machine>/secrets.nix` and adds its import to
   `configuration.nix`
4. Adds the machine to `lib/ssh-hosts.nix` with the login key under
   `userPublicKeys.<user>`
5. Re-keys all secrets so the machine is a recipient

The private key is decrypted at runtime by agenix and deployed by home-manager.
The public key recorded in `lib/ssh-hosts.nix` is added to that user's
`openssh.authorizedKeys.keys` on every machine that declares them — no manual
`authorized_keys` editing.

For machines already provisioned, the corresponding
`thomasga/ssh-id-ed25519-<machine>.age` secret already exists; run the
enrollment script and skip the key generation step if you only need to register a
new machine's identity.

`tools/bootstrap_ssh_key.py` is the lower-level helper `enroll.py` uses to create
and encrypt the keypair. Call it directly only when repairing a partially
enrolled machine.

## Collect And Pin The Host Key After Deploy

The deployed machine generates its own SSH **host** keypair automatically when
sshd starts. This is separate from the login keypair above; it is what remote
machines use to verify they are talking to the correct host.

NixOS generates `/etc/ssh/ssh_host_ed25519_key` and its `.pub` on first boot with
sshd enabled. The private key stays on the machine unencrypted (standard SSH
practice); only the public key belongs in the repo.

After the machine boots for the first time:

1. Collect the host's public key:

   ```bash
   ssh-keyscan -t ed25519 <machine> 2>/dev/null
   ```

   This prints a line like:

   ```text
   enterprise-d ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDCRCqI2...
   ```

2. Verify the fingerprint out-of-band — log in to the machine and compare:

   ```bash
   ssh-keygen -l -f /etc/ssh/ssh_host_ed25519_key.pub
   ```

3. Paste the key portion into `lib/ssh-hosts.nix` as
   `publicKey = "ssh-ed25519 AAAA..."` for that machine.

Verify the fingerprint before committing. `ssh-keyscan` is a collection
mechanism, not a trust oracle.
