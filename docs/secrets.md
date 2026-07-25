# Secrets

This repo uses agenix for committed secrets and Bitwarden for recovery material.
Secrets live in `secrets/` and are safe to commit; only the decrypted content is
sensitive.

SSH key management is a separate concern — see [docs/ssh.md](ssh.md).

## Model

Secrets never exist as plaintext on disk. The flow is:

1. Encrypted `.age` files are committed to `secrets/`.
2. `secrets/secrets.nix` declares which age public keys (hosts plus the offline
   admin) can decrypt each file.
3. `age.secrets.*` entries declared in each host's `secrets.nix` are decrypted at
   activation time into `/run/agenix/` (tmpfs).
4. NixOS modules and home-manager reference `/run/agenix/<name>` paths.

Runtime decryption uses the dedicated age private key at
`/var/lib/agenix/identity`, configured by `modules/secrets.nix` — that module
sets the identity path and nothing else. Every host has its own
`hosts/<machine>/secrets.nix` declaring the `age.secrets` for that machine.

The offline admin private key lives **only** in Bitwarden. It is never installed
on a machine permanently; it is placed temporarily when rekeying and shredded
afterwards.

## Generating Age Identities

Run these from the repo root inside `nix develop`. Confirm the tooling is
present first:

```bash
command -v age
command -v agenix
printf '%s\n' "$EDITOR"
```

If `EDITOR` is empty, set it before using `nix run .#secret-edit` — either
inline (`EDITOR=nano nix run .#secret-edit -- ...`) or `export EDITOR=nano` for
the session.

1. Generate the offline admin age identity, outside the repo:

   ```bash
   mkdir -p ~/.config/agenix
   chmod 700 ~/.config/agenix
   age-keygen -o ~/.config/agenix/admin.age
   chmod 600 ~/.config/agenix/admin.age
   ```

2. Generate a host-specific age identity:

   ```bash
   age-keygen -o ~/.config/agenix/<machine>.age
   chmod 600 ~/.config/agenix/<machine>.age
   ```

3. Copy the public keys printed by `age-keygen` into `secrets/secrets.nix` —
   `offlineAdmin` for the recovery key, and the machine name for the host key.

4. Store the offline admin private key, or its recovery material, in Bitwarden.
   Do not install that key onto machines.

5. Install the host private key onto the target. During a first install,
   `tools/install.py` handles this interactively; to do it manually against a
   mounted target:

   ```bash
   sudo python3 tools/install_age_identity.py --file ~/.config/agenix/<machine>.age
   ```

   Pass `--shred` to erase the source file after copying.

6. On an already-installed machine, install or rotate the host identity in place:

   ```bash
   sudo python3 tools/install_age_identity.py --file ~/.config/agenix/<machine>.age \
     --target /var/lib/agenix/identity
   ```

In practice `tools/enroll.py` does steps 2-3 for you as part of enrolling a new
machine — see [docs/provisioning.md](provisioning.md#step-2--enroll-the-machine).

## Creating Or Rotating a Secret

Never create plaintext files under `secrets/`. Use the helper command so the
plaintext only ever exists in a temporary editor buffer.

For a brand-new secret:

1. Add a recipient entry to `secrets/secrets.nix`:

   ```nix
   "thomasga/nas-smb-credentials.age".publicKeys = [enterprise-d offlineAdmin];
   ```

2. Create or edit the encrypted file:

   ```bash
   EDITOR=nano nix run .#secret-edit -- secrets/thomasga/nas-smb-credentials.age
   ```

3. If NixOS or home-manager needs a runtime path for that secret, expose it
   through `age.secrets` in the host's `secrets.nix` (e.g.
   `hosts/enterprise-d/secrets.nix`).

To rotate an existing secret, run the same `secret-edit` command against it.

After changing recipients in `secrets/secrets.nix`, re-encrypt every tracked
secret with the offline admin key available locally:

```bash
# The offline admin age private key must be present at ~/.config/agenix/admin.age
# on the machine running this command. Retrieve it from Bitwarden first if needed:
mkdir -p ~/.config/agenix && chmod 700 ~/.config/agenix
# paste key material into ~/.config/agenix/admin.age, then:
chmod 600 ~/.config/agenix/admin.age
nix run .#secret-rekey
shred -u ~/.config/agenix/admin.age
```

## Scope For Future Hosts

When you add another host, generate a separate age identity for it and add its
public key to `secrets/secrets.nix` under a new host name. Only add that host to
the recipient list for the secrets it actually needs. Do not widen existing
recipient lists just because a new machine exists.

## Secret Inventory

Exact plaintext contents matter — these files are consumed by tools that parse
them strictly.

### Restic repository passwords

Each decrypts to exactly one plaintext line:

```text
correct-horse-battery-staple
```

No `password=` prefix, no quotes, no JSON.

There is one restic-password secret **per backup job**, keyed to the entry name
under `custom.backups.users`, not to the machine — each entry gets its own
restic repository. `passwordFile` defaults to
`/run/agenix/<name>/restic-password`.

| Secret | Backup job |
| --- | --- |
| `secrets/thomasga/restic-password.age` | `thomasga` (home directory) |
| `secrets/hass/restic-password.age` | `hass` |
| `secrets/zigbee2mqtt/restic-password.age` | `zigbee2mqtt` |
| `secrets/zwave-js/restic-password.age` | `zwave-js` |
| `secrets/adguardhome/restic-password.age` | `adguardhome` |

### NAS SMB credentials

`secrets/thomasga/nas-smb-credentials.age` and
`secrets/defiant/nas-smb-credentials.age` decrypt to:

```text
username=nas-user
password=nas-password
```

### Wi-Fi passphrases

Each Wi-Fi secret decrypts to exactly one line — the variable name and password,
no quotes, no other lines:

```text
WIFI_AGT_HOME_PASSWORD=your-passphrase-here
```

| Secret file | Variable name | Network |
| --- | --- | --- |
| `wifi/agt-home.age` | `WIFI_AGT_HOME_PASSWORD` | `agt-home` |
| `wifi/agt-iot.age` | `WIFI_AGT_IOT_PASSWORD` | `agt-iot` |
| `wifi/agt-work.age` | `WIFI_AGT_WORK_PASSWORD` | `agt-work` |

### defiant service secrets

| Secret | Contents |
| --- | --- |
| `defiant/cloudflare-api-token.age` | `CF_DNS_API_TOKEN=<Cloudflare Zone:DNS:Edit token>` |
| `defiant/location.age` | ADS-B receiver location, as `VAR=value` lines |
| `defiant/zigbee-network-key.age` | A bracketed byte array, e.g. `[12,34,...,255]` |
| `defiant/zwave-secrets.age` | JSON with one `securityKeys` object |

`defiant/zwave-secrets.age` must look exactly like this:

```json
{
  "securityKeys": {
    "S0_Legacy": "<hex>",
    "S2_Unauthenticated": "<hex>",
    "S2_Authenticated": "<hex>",
    "S2_AccessControl": "<hex>"
  }
}
```

Generate both sets of keys **before the first deploy**. Neither Zigbee2MQTT nor
Z-Wave JS generates a working key on its own, and regenerating either after
devices are paired or included breaks every one of them, requiring a full
re-pair:

```bash
python3 -c "import secrets; print('[' + ','.join(str(b) for b in secrets.token_bytes(16)) + ']')"

for name in S0_Legacy S2_Unauthenticated S2_Authenticated S2_AccessControl; do
  echo "$name=$(openssl rand -hex 16)"
done
```

## What May Be Committed

Safe to commit:

- `secrets/**/*.age`
- `secrets/secrets.nix`

Never commit:

- plaintext secret files
- age private keys
- decrypted copies of secrets
- Bitwarden exports or recovery bundles

The repo is set up to make mistakes harder:

- `.gitignore` ignores common plaintext scratch files and local key material
- `pre-commit` rejects staged plaintext files under `secrets/`
- `pre-commit` rejects raw private keys anywhere in the repo

## Wi-Fi Credentials

Wi-Fi profiles are declared in `roles/common/wifi.nix` using
`networking.networkmanager.ensureProfiles`. The SSID is stored in plaintext in
the config; the passphrase is kept in an agenix secret and substituted at
activation time. NetworkManager writes the final profile to
`/etc/NetworkManager/system-connections/` (0600, root-only) — the same location
and permissions as any manually configured connection. LUKS encryption protects
those files at rest, and the agenix secret itself lives on tmpfs (`/run/agenix/`)
and is never written to disk.

`roles/common/networking.nix` is a separate file for network *discovery*
(avahi/mDNS) and is not involved in Wi-Fi.

Currently configured networks: `agt-home`, `agt-iot`, `agt-work`.

### Creating the Wi-Fi secrets

One per network, run once each:

```bash
EDITOR=nano nix run .#secret-edit -- secrets/wifi/agt-home.age
EDITOR=nano nix run .#secret-edit -- secrets/wifi/agt-iot.age
EDITOR=nano nix run .#secret-edit -- secrets/wifi/agt-work.age
```

See the Wi-Fi table under [Secret Inventory](#wi-fi-passphrases) for the
variable name each network requires.

### Adding another network

Three files change, and one new secret is created:

1. `secrets/secrets.nix` — add a recipient entry:

   ```nix
   "wifi/newnet.age".publicKeys = [enterprise-d offlineAdmin];
   ```

2. `roles/common/wifi.nix` — expose the secret at runtime, alongside the existing
   Wi-Fi entries:

   ```nix
   "wifi/newnet".file = ../../secrets/wifi/newnet.age;
   ```

3. `roles/common/wifi.nix` — add the secret path to `environmentFiles` and add a
   profile block:

   ```nix
   environmentFiles = [
     # existing entries...
     config.age.secrets."wifi/newnet".path
   ];
   profiles."newnet-ssid" = {
     connection = {id = "newnet-ssid"; type = "wifi";};
     wifi = {ssid = "newnet-ssid"; mode = "infrastructure";};
     wifi-security = {key-mgmt = "wpa-psk"; psk = "$WIFI_NEWNET_PASSWORD";};
     ipv4.method = "auto";
     ipv6.method = "auto";
   };
   ```

   The `$WIFI_NEWNET_PASSWORD` placeholder must match the variable name inside
   the secret file exactly.

4. Create the encrypted secret:

   ```bash
   EDITOR=nano nix run .#secret-edit -- secrets/wifi/newnet.age
   ```

   File contents: `WIFI_NEWNET_PASSWORD=your-passphrase`

### Verifying Wi-Fi profiles

After `sudo nixos-rebuild switch --flake .#enterprise-d`:

```bash
nmcli connection show
sudo cat /etc/NetworkManager/system-connections/agt-home.nmconnection
```

## Disk Encryption And TPM

`enterprise-d` encrypts the root filesystem with LUKS and seals it to the
machine's TPM 2.0 chip.

### The LUKS passphrase

The disko configuration creates an encrypted root partition. `tools/install.py`
prompts for a LUKS passphrase interactively during provisioning. That passphrase
unlocks the root filesystem whenever the TPM is unavailable or tampered with.

Save it in Bitwarden or another secure location **outside** the machine. You will
need it if:

- The TPM is reset or replaced
- The firmware is updated and TPM state is cleared
- You boot from a rescue USB and need to unlock the disk manually

### Enrolling and verifying the TPM

The enrollment and verification commands, including the PCR selection and what
each PCR measures, live in
[hosts/enterprise-d/README.md](../hosts/enterprise-d/README.md#tpm-auto-unlock).
That is the canonical copy.

### Change or reset the LUKS passphrase

To change the passphrase while the system is running:

```bash
sudo cryptsetup luksChangeKey /dev/disk/by-partlabel/root
```

To wipe the passphrase slot and rely entirely on TPM2 unlock:

```bash
sudo systemd-cryptenroll /dev/disk/by-partlabel/root --wipe-slot=password
```

### TPM recovery and troubleshooting

If the system does not auto-unlock at boot:

1. **At the initrd prompt** you will be asked for the LUKS passphrase. Enter the
   passphrase you created during install.
2. **If you forgot the passphrase**, boot from a NixOS rescue USB and use
   standard LUKS recovery tools.
3. **If the TPM appears broken**, re-enroll the passphrase and optionally
   re-enroll TPM2 after the system boots.
4. **If Secure Boot or firmware state changed**, the TPM may not unlock
   automatically. Either provide the passphrase or re-enroll TPM after boot.
