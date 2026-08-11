# Backups

Client-pushed restic backups to a NAS share, provided by
`modules/backups.nix` and configured per host through `custom.backups`.

The module is imported by `modules/default.nix`, so every host already has
it — a host only needs to set `custom.backups`.

**Backups are mandatory.** `profiles/common/base.nix` — imported by every real
host, but deliberately not by `flake.nix`'s module-inertness probe — asserts
`custom.backups.enable` is true, so a machine that never configures backups
fails to evaluate rather than shipping unprotected. There is no opt-out:
define a `custom.backups` block for every host.

`custom.backups.backrest` (owned by `homelab-network` — see
[docs/homelab-network.md](homelab-network.md)) is the fleet-wide restic
snapshot browser/restore UI, reverse-proxied through the Traefik host
(currently `reliant`). To add or remove a host from that cross-host proxy,
edit `lib/backrest-hosts.nix` — it's the single source of truth both
`custom.dns.subdomains` and `custom.backups.backrest.proxiedRemotes` derive
from on the Traefik host, so the two lists can't drift out of sync.

Each domain agent adds the entries for its own services (the same way each adds
its own `custom.dns.subdomains`): `smart-home` owns the `hass`, `zigbee2mqtt`,
and `zwave-js` entries, `homelab-network` owns `adguardhome`, and
`user-provisioner` owns the per-person home-directory entries.

## How Backups Run

The NAS share is mounted on demand over SMB or NFS. Backups run on a daily
timer. On hosts marked as laptops they only run when AC power is connected. If
the NAS is unreachable, the job exits cleanly.

Each enabled entry gets its own systemd service (`nas-backup-<name>`) and timer
(`nas-backup-<name>-timer`). The service:

1. Triggers an automount of the NAS share.
2. Exits silently if the share is not reachable.
3. Initialises a restic repository if — and only if — one is not already there.
   The check is the presence of `<repo>/config` on the mounted share, and an
   `init` that still reports `config file already exists` is treated as success,
   so a re-run over an existing repository is a no-op rather than a failure.
4. Canonicalises each configured path with `readlink -f` and backs up the
   result (default: `/home/<name>`, excluding `.cache`) — see
   [Symlinked State Directories](#symlinked-state-directories) for why.
5. Prunes old snapshots according to the retention policy — 7 daily, 4 weekly,
   12 monthly, 3 yearly by default. That progressively reduces granularity over
   time while keeping long-term coverage.

Each entry gets its **own restic repository**, and therefore its own
`restic-password` secret, keyed to the entry name rather than the machine.

The service runs as root, and systemd gives root services no `$HOME`, so restic
cannot pick a cache directory on its own. The unit therefore declares
`CacheDirectory` and points `RESTIC_CACHE_DIR` at it: each entry caches in
`/var/cache/nas-backup-<name>`, one directory per repository. Deleting that
directory is safe — restic rebuilds it on the next run, more slowly.

## Enabling Backups On A Host

**1. Create the two secrets a backup entry needs**: an SMB credentials secret
and a restic password secret, each exposed at a known path in the host's
`secrets.nix`. The exact plaintext format for each, and the create/rotate
command, are in
[docs/secrets.md § Secret Inventory](secrets.md#secret-inventory) — don't
improvise the format, it's parsed strictly.

**2. Set the NAS coordinates and enable the entries** in the host configuration:

```nix
custom.isLaptop = true; # omit or set false for non-laptops

custom.backups = {
  enable = true;

  nas = {
    host = "192.168.1.x"; # or a hostname, if DNS resolves it
    share = "backups";
    credentialsFile = "/run/agenix/thomasga/nas-smb-credentials";
  };

  users.thomasga.enable = true;
};
```

Use `nas.protocol = "nfs"` and omit `credentialsFile` to switch to NFS.

`lib/nas.nix` holds the shared NAS constants (`ip`, `host`, `shares`); prefer
importing it over hardcoding the address.

**3. Rebuild the host.**

## Backing Up Service State Outside `/home`

Override `paths` explicitly. Example from `defiant`, backing up Home Assistant:

```nix
custom.backups.users = {
  hass = {
    enable = true;
    paths = ["/var/lib/hass"];
    excludePatterns = ["/var/lib/hass/.storage/lovelace*"];
  };
};
```

`passwordFile` defaults to `/run/agenix/<name>/restic-password`; override it only
if the secret does not follow that convention.

## Symlinked State Directories

A service that runs under systemd's `DynamicUser` gets its `StateDirectory=` or
`CacheDirectory=` as a **symlink**, not a directory: systemd creates the real
directory at `/var/lib/private/<name>` and leaves `/var/lib/<name>` pointing at
it. `/var/lib/AdGuardHome` and `/var/cache/zwave-js` are both of this shape;
`/var/lib/hass` and `/var/lib/zigbee2mqtt` are ordinary directories.

**restic does not dereference a symlink passed to it as a top-level backup
path.** It records the symlink node and never walks the target. A `paths` entry
pointing at one of these state directories therefore produced snapshots
containing only the bare path components (`/var`, `/var/lib`,
`/var/lib/AdGuardHome`) and nothing underneath — 0 B, indefinitely, with the job
reporting success. This was confirmed live: every `adguardhome` and `zwave-js`
snapshot taken before this was fixed was empty.

The backup service therefore resolves each configured path through
`readlink -f` **at runtime, inside the unit**, and hands restic the resolved
path. It cannot be done at evaluation time — the path exists only on the host
being backed up, not on whatever machine builds the configuration. Resolution is
a no-op for an ordinary directory, so non-symlink entries are unaffected.

Consequences to be aware of:

- **Snapshots record the resolved path.** `restic snapshots` for the
  `adguardhome` repo shows `/var/lib/private/AdGuardHome`, not
  `/var/lib/AdGuardHome`. Restores need the resolved path, and because
  `restic forget` groups by host *and* paths by default, pre-fix snapshots form
  a separate retention group that ages out on its own. Delete the old empty
  snapshots by hand if they are in the way.
- **Exclude patterns still use the configured path.** Write
  `excludePatterns` against the path as configured. The unit re-emits any
  pattern prefixed by a path that resolved elsewhere against the resolved
  prefix as well, so both forms are passed to restic and either spelling
  matches.
- **Keep `paths` pointing at the symlink**, not at
  `/var/lib/private/<name>`. The symlink is the stable, documented interface;
  the private path is a systemd implementation detail that also carries
  restrictive permissions.

## Checking Backup Status

```bash
# List timers and see when the next backup runs
systemctl list-timers 'nas-backup-*'

# Run a backup immediately
sudo systemctl start nas-backup-thomasga.service

# View the backup log
journalctl -u nas-backup-thomasga.service

# List restic snapshots on the NAS
sudo restic --repo /mnt/nas-backups/thomasga/<hostname> snapshots

# Confirm a job is actually storing data, not an empty tree. A snapshot whose
# listing stops at the top-level path with nothing under it is the symlink
# failure described above.
sudo restic --repo /mnt/nas-backups/adguardhome/<hostname> ls latest | head
```

`RESTIC_PASSWORD_FILE=/run/agenix/<name>/restic-password` has to be exported for
those commands, or restic prompts for the passphrase.

## Limitations

- Snapper manages local btrfs snapshots for rollback. It is not involved in NAS
  backups.
- If SMB is unavailable at boot the automount fails silently, and the next timer
  invocation retries.
- The services are `wantedBy = multi-user.target`, so a `nixos-rebuild switch`
  restarts them and starts a backup immediately. If that interrupts a run in
  progress, restic may leave a lock behind; restic clears its own stale locks on
  the following run, and `restic --repo <repo> unlock` forces it.
- Service state paths are case-sensitive and not always what the service name
  suggests — `defiant` backs up `/var/lib/AdGuardHome`, capitalized, because the
  lowercase path does not exist. Confirm with `ls -l` on the host before adding
  an entry; that also shows whether the path is a symlink, which matters for the
  reason given in [Symlinked State Directories](#symlinked-state-directories).
- `custom.backups.backrest`'s seed `config.json` only replaces an existing file
  after `backrest.service` has actually failed to start against it several
  times in a row (`systemd`'s own `NRestarts` counter, `>= 4`) — trusting
  backrest's own verdict on whether the file loads, not this module
  re-guessing backrest's validation rules externally. Gated on *repeated*
  failures, not the first one, so a transient NAS/network hiccup on startup
  isn't mistaken for a broken config and doesn't clobber real UI-managed state
  (plans, schedules). Confirmed live on excelsior and reliant: before this
  existed, a plain existence check alone meant a `config.json` broken by a
  pre-fix seed never self-healed just because the generated seed was later
  fixed — `backrest.service` crash-looped against the stale file across
  several redeploys until it was removed by hand:
  `sudo rm /var/lib/backrest/config.json && sudo systemctl restart backrest`.
