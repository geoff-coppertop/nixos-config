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

Each domain agent adds the entries for its own services (the same way each adds
its own `custom.dns.subdomains`): `smart-home` owns the `hass`, `zigbee2mqtt`,
and `zwave-js` entries, `homelab-network` owns `adguardhome`,
`user-provisioner` owns the per-person home-directory entries, and `architect`
owns `bambuddy` — the one service whose `custom.*` module no specialist owns.

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
    share = "Backups";
    credentialsFile = "/run/agenix/backup-svc/nas-smb-credentials";
  };

  users.adguardhome.enable = true;
};
```

That `nas` block is the host's **default** NAS target: every entry under
`users.*` uses it unless the entry overrides it. Jobs on one host are not
required to share a single target — see
[Pointing One Entry At A Different NAS Target](#pointing-one-entry-at-a-different-nas-target).

Shared and appliance backup jobs authenticate with **`backup-svc`**, a
dedicated NAS account scoped to the `Backups` share. The restic repository path
embeds the hostname, so hosts sharing that account do not collide. `media-svc`
is separate again for `excelsior`'s Jellyfin library — see
[docs/secrets.md § NAS SMB credentials](secrets.md#nas-smb-credentials).

A **person's own home-directory backup is the exception**: it keeps using that
person's own NAS login against `Personal-Drive`, not the shared service
account. On a host where that is the only backup job the host-wide `nas` block
is simply set to the personal credential and share; on a host where it sits
next to appliance jobs, the entry carries its own NAS target — see
[Pointing One Entry At A Different NAS Target](#pointing-one-entry-at-a-different-nas-target).

Use `nas.protocol = "nfs"` and omit `credentialsFile` to switch to NFS.

`lib/nas.nix` holds the shared NAS constants (`ip`, `host`, `shares`); prefer
importing it over hardcoding the address. `shares` names three independent
top-level shares — `Personal-Drive`, `Backups`, `Media` — each with its own
NAS-side account.

**3. Rebuild the host.**

## Backing Up Service State Outside `/home`

Override `paths` explicitly. Example from `reliant`, backing up Home Assistant:

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

## Pointing One Entry At A Different NAS Target

`custom.backups.users.<name>.nas` is an optional per-entry override of the
host-wide `custom.backups.nas` block. It takes the same six attributes
(`host`, `share`, `protocol`, `credentialsFile`, `mountPoint`, `mountOptions`)
and the same defaults, and is `null` by default — an entry that does not set
it behaves exactly as before, using the host's shared mount.

Use it when **one job on a host needs a different NAS account, share, or host
than the rest of the machine**. The concrete case: `reliant` and `excelsior`
run appliance jobs (`hass`, `zigbee2mqtt`, `zwave-js`, `adguardhome`,
`dcs-server`, `factorio`) under the shared `backup-svc` account on the
`Backups` share, while the same hosts also back up `thomasga`'s home directory,
which must stay on that person's own NAS login against `Personal-Drive`. Both
kinds of job coexist on one host:

```nix
custom.backups = {
  enable = true;

  # Host default: the shared service account, used by every entry below that
  # does not override it.
  nas = {
    credentialsFile = "/run/agenix/backup-svc/nas-smb-credentials";
    inherit (nas) host;
    share = nas.shares.backups;
  };

  users = {
    thomasga = {
      enable = true;
      nas = {
        credentialsFile = "/run/agenix/thomasga/nas-smb-credentials";
        inherit (nas) host;
        # The pre-existing home-directory repository location, not the bare
        # Personal-Drive share — see lib/nas.nix's personalBackups comment.
        share = nas.shares.personalBackups;
        mountPoint = "/mnt/nas-personal-backups";
      };
    };

    adguardhome = {
      enable = true;
      paths = ["/var/lib/AdGuardHome"];
      excludePatterns = [];
    };
  };
};
```

What an override changes for that entry:

- It gets its **own CIFS/NFS mount**, with its own credentials and device path,
  separate from the host-wide one. The mount point defaults to
  `/mnt/nas-<share, lowercased>` — the same derivation the host-wide block
  uses — so it is named after what it actually holds, not after which entry
  or module slot asked for it. That default only works cleanly for a bare
  share name; `nas.shares.personalBackups` is `Personal-Drive/backups` (a
  share plus a subpath, predating the top-level `Backups` share and not to be
  confused with it), so the example above sets `mountPoint` explicitly to
  `/mnt/nas-personal-backups` rather than let it derive a slash into the
  path. Set `mountPoint` explicitly whenever the derived name would collide,
  contain a slash, or you just want something else.
- Its restic repository moves with it, to
  `<mountPoint>/<name>/<hostname>` — so `/mnt/nas-personal-backups/thomasga/reliant`
  in the example above. The status and unlock commands below need that path,
  not `/mnt/nas-backups/...`.
- **Get the `share` value right the first time.** The mount point is only a
  local label — what actually matters is which remote path the restic
  repository lands in. Pointing an override at the wrong share (even one
  that looks similar, like the bare `Personal-Drive` root instead of
  `Personal-Drive/backups`) doesn't fail loudly: restic just finds no
  existing repository there and silently creates a brand-new, empty one,
  orphaning the real history at the old path. There is no assertion that can
  catch this — a wrong-but-well-formed share is indistinguishable from a
  deliberate new one. Confirm the target with `restic snapshots` (checking
  dates, not just that it lists *something*) before trusting a job's first
  post-change run.
- The `host`/`share`/`credentialsFile` assertions are enforced against the
  override, so a half-filled block fails evaluation with a
  `custom.backups.users.<name>.nas.…` message rather than mounting garbage.

Everything else — schedule, retention, password file, path canonicalisation —
is unchanged and still host-wide.

On a host where the personal home-directory job is the *only* backup job
(`enterprise-d`, `holodeck-01`), no override is needed: set the host-wide `nas`
block to the personal credential and `nas.shares.personalBackups` directly
(same caveat about the exact share value applies there too).

The secret side is `secrets-warden`'s: an overriding entry's
`credentialsFile` needs that host to be a recipient of the secret and to
declare the matching `age.secrets` entry, or the mount fails at runtime.

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

# List restic snapshots on the NAS — thomasga always mounts
# Personal-Drive/backups (host-wide on enterprise-d/holodeck-01, an override
# on reliant/excelsior) at /mnt/nas-personal-backups, never /mnt/nas-backups
sudo restic --repo /mnt/nas-personal-backups/thomasga/<hostname> snapshots

# Confirm a job is actually storing data, not an empty tree. A snapshot whose
# listing stops at the top-level path with nothing under it is the symlink
# failure described above.
sudo restic --repo /mnt/nas-backups/adguardhome/<hostname> ls latest | head
```

`RESTIC_PASSWORD_FILE=/run/agenix/<name>/restic-password` has to be exported for
those commands, or restic prompts for the passphrase.

Every entry's `--repo` path is `<its mount point>/<name>/<hostname>` — the
host-wide default (`/mnt/nas-backups`, `Backups` share) for an entry with no
override, or its own mount point (like `/mnt/nas-personal-backups` above) for
one that has a `custom.backups.users.<name>.nas` block.

## Clearing A Stale restic Lock

A job that is killed mid-run — most often by a `nixos-rebuild switch` restarting
the unit while a backup is in flight — leaves an exclusive lock in the
repository. The next run fails with:

```text
unable to create lock in backend: repository is already locked by PID 3267 on <host> by root
```

**restic will not always clear that lock for you.** It treats a lock as stale
only when the recorded host+PID pair is verifiably dead — for a lock recorded on
the same host, that is a liveness probe against the recorded PID. After a
reboot, or simply after enough process churn, the kernel recycles that PID onto
an unrelated live process, restic sees the "holder" as still running, and the
lock persists indefinitely. `--retry-lock` does not help here: waiting five
minutes for a holder that no longer exists just delays the same failure.

Unlock it by hand and re-run the job. Every path below is derived from the entry
name `<name>` (the attribute under `custom.backups.users`) and the host name:

```bash
sudo env RESTIC_PASSWORD_FILE=/run/agenix/<name>/restic-password \
  RESTIC_CACHE_DIR=/var/cache/nas-backup-<name> \
  restic --repo /mnt/nas-backups/<name>/<hostname> unlock
sudo systemctl start nas-backup-<name>.service
```

Concretely, for `thomasga` on `enterprise-d`:

```bash
sudo env RESTIC_PASSWORD_FILE=/run/agenix/thomasga/restic-password \
  RESTIC_CACHE_DIR=/var/cache/nas-backup-thomasga \
  restic --repo /mnt/nas-personal-backups/thomasga/enterprise-d unlock
sudo systemctl start nas-backup-thomasga.service
```

Substitute `passwordFile` if the entry overrides it, and the entry's own mount
point if it does not use the host-wide `/mnt/nas-backups` default — either
because the host sets `custom.backups.nas.mountPoint` explicitly, or because
the entry has its own `custom.backups.users.<name>.nas` block with its own
`mountPoint` (see
[Pointing One Entry At A Different NAS Target](#pointing-one-entry-at-a-different-nas-target)).

Only unlock when no backup for that entry is actually running — check
`systemctl is-active nas-backup-<name>.service` first. Unlocking underneath a
live run is what the lock exists to prevent.

## Limitations

- Snapper manages local btrfs snapshots for rollback. It is not involved in NAS
  backups.
- If SMB is unavailable at boot the automount fails silently, and the next timer
  invocation retries.
- The services are `wantedBy = multi-user.target`, so a `nixos-rebuild switch`
  restarts them and starts a backup immediately. Both restic invocations pass
  `--retry-lock 5m`, so a run that overlaps another one waits for the lock
  instead of failing outright. A run that is *killed* mid-flight still leaves a
  lock behind, and that one does not clear itself — see
  [Clearing A Stale restic Lock](#clearing-a-stale-restic-lock).
- Service state paths are case-sensitive and not always what the service name
  suggests — AdGuard Home's is `/var/lib/AdGuardHome`, capitalized, because the
  lowercase path does not exist (confirmed on `reliant`). Confirm with `ls -l`
  on the host before adding an entry; that also shows whether the path is a
  symlink, which matters for the reason given in
  [Symlinked State Directories](#symlinked-state-directories).

## Known Gotchas

- `--retry-lock 5m` on both restic invocations in `modules/backups.nix` covers
  overlapping runs but not an orphaned lock: restic's staleness check trusts the
  recorded PID's liveness, which PID reuse across a reboot defeats, so such a
  lock never ages out and needs
  [Clearing A Stale restic Lock](#clearing-a-stale-restic-lock).
