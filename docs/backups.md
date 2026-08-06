# Backups

Client-pushed restic backups to a NAS share, provided by
`modules/backups.nix` and configured per host through `custom.backups`.

The module is imported by `modules/default.nix`, so every host already has
it — a host only needs to set `custom.backups`.

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
4. Backs up the configured paths (default: `/home/<name>`, excluding `.cache`).
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
```

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
  lowercase path does not exist. Confirm with `ls` on the host before adding an
  entry.
