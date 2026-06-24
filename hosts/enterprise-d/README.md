# enterprise-d

## Machine Files

- Host entrypoint: `hosts/enterprise-d/configuration.nix`
- Hardware: `hosts/enterprise-d/hardware.nix`
- Power tuning and hibernation policy: `hosts/enterprise-d/power.nix`
- Disk layout: `hosts/enterprise-d/disko.nix`
- Flake entry: `flake.nix`

## Installation

### Post-Install Checklist

After the system boots:

1. **Enroll TPM2 for LUKS auto-unlock** (see [TPM Auto-Unlock](#tpm-auto-unlock))
2. **Collect the SSH host public key** and add it to `lib/ssh-hosts.nix` (see the main [README](../../README.md))
3. **Generate and install your SSH login credentials** (see the main [README](../../README.md))
4. **Test hibernation** (see [Verification](#verification))
5. **Validate the system** (see the main [README](../../README.md))

### TPM Auto-Unlock

After the system boots and you are logged in, enroll the LUKS key into the TPM:

```bash
sudo systemd-cryptenroll /dev/disk/by-partlabel/root --tpm2-device=auto --tpm2-pcrs=0,1,3,7
```

The `--tpm2-pcrs` argument seals the key to specific firmware/bootloader measurements:

- `0`: firmware configuration
- `1`: bootloader configuration
- `3`: bootloader state
- `7`: Secure Boot state

After enrollment, reboot. The system should now unlock automatically at boot without a passphrase prompt.

### Verify TPM Enrollment

To check that TPM enrollment is active:

```bash
sudo systemd-cryptenroll /dev/disk/by-partlabel/root --json | jq '.[] | select(.type=="tpm2")'
```

A non-empty result confirms TPM2 enrollment is active.

## Philosophy

- **On AC:** the system runs continuously. Lid close blanks and locks the screen but does not suspend. Long-running processes (builds, compiles) are never interrupted.
- **On battery:** power is conserved aggressively. The system suspends quickly on idle or lid close, then hibernates after 10 minutes of being suspended.

## Behaviour By Scenario

### AC power — user logged in

| Trigger | Action |
| --- | --- |
| Lid close | Screen blanks and locks — system keeps running |
| 4 min idle | Screen blanks and locks |
| AC removed while idle | Battery rules apply immediately; suspend fires within 5 min of idle |
| AC removed while active | Battery idle countdown begins once user stops interacting |

### Battery — user logged in

| Trigger | Action |
| --- | --- |
| Lid close | Suspend immediately, hibernate after 10 min |
| 4 min idle | Screen blanks and locks |
| 5 min idle | Suspend, hibernate after 10 min — forced even if an app holds a suspend inhibitor |
| 10 min suspended | Hibernate |
| Critical battery | Immediate hibernate, bypassing suspend |

On battery, sustained idle always wins: logind's `IdleAction` suspends at ~4.5 min when nothing inhibits, and the `battery-idle-suspend` watchdog forces `systemctl suspend -i` at 5 min if an application (e.g. a Firefox tab "Playing video") holds a suspend inhibitor that would otherwise block it indefinitely. The forced suspend relies on a polkit rule granting root the `suspend-ignore-inhibit` action non-interactively (the watchdog is a system service with no auth agent). Each forced suspend is logged under `journalctl -t battery-idle-suspend`.

### GDM login screen (no user logged in)

Behaviour is identical on AC and battery — there are no running user processes to protect.

| Trigger | Action |
| --- | --- |
| 30 s idle | Suspend, hibernate after 10 min |
| 10 min suspended | Hibernate |

The 30 s window applies from when the login screen goes idle, which itself follows GNOME's default `idle-delay`. In practice the screen is unattended from first appearance, so this fires approximately 30 s after GDM starts.

## Resuming

- **From suspend (s2idle):** open the lid or press the power button.
- **From hibernate:** press the power button. Opening the lid does not resume from hibernate — this is a Framework EC firmware limitation with no Linux-side workaround.

## Implementation

| File | Responsibility |
| --- | --- |
| `hosts/enterprise-d/power.nix` | logind lid/key actions, `IdleAction`, RTC wakeup kernel param, `hibernate-trigger` system-sleep hook (arms RTC wakealarm, decides hibernate on resume, logging) |
| `roles/desktop/power.nix` | `logind-idle-inhibitor` user service (blocks logind `IdleAction` only while on AC) and the `battery-idle-suspend` watchdog (forces `suspend -i` on battery past 5 min idle, overriding application inhibitors, via a root polkit grant); shared Mains-only AC-detection helper |
| `users/thomasga/gnome.nix` | GNOME idle/sleep dconf settings: screen blank at 4 min, battery sleep at 5 min, lock on blank, critical battery hibernate |

### Why a self-owned RTC trigger instead of `suspend-then-hibernate`

`suspend-then-hibernate` previously failed to reach hibernate reliably,
roughly 43% of cycles in testing. The kernel boot parameter
`rtc_cmos.use_acpi_alarm=1` (still set, see below) addresses a related but
distinct AMD/EC timing issue — it switches RTC wakeup to ACPI alarms
instead of HPET, avoiding an `rtc->aie_timer` mismatch in the `amd-pmc`
driver's timer-based S0i3 wakeup handling — but it did not fix the failures
seen here, because the actual cause is a separate, upstream bug inside
systemd itself: a zero-timeout `POLLIN` race in `custom_timer_suspend()`
(`src/sleep/sleep.c`, tracked as `systemd/systemd#38193`, open/unfixed),
where the RTC/EC wake reaches the process before systemd's own poll on the
timerfd reports readable, so systemd treats the wake as user-initiated and
skips hibernate.

Since the race is in systemd's own internal timer logic, not at the
RTC/EC hardware layer, the fix is to stop using `suspend-then-hibernate`
entirely. `HandleLidSwitch` and `IdleAction` are both set to plain
`suspend`, and a `/etc/systemd/system-sleep/hibernate-trigger` hook (an
officially documented, stable systemd extension point — not a patch
against, or override of, unit internals) arms `/sys/class/rtc/rtc0/wakealarm`
directly on suspend and, on resume, makes its own non-racy decision based
on wall-clock elapsed time: if elapsed time is close enough to the
configured delay, the RTC alarm fired as scheduled and the hook triggers
`systemctl hibernate`; otherwise a real user action woke the machine early
and nothing further happens. This replaces both `suspend-then-hibernate`
and the earlier, abandoned patched-`systemd` approach (PR#52) that
regressed hibernate entirely; neither is used here. No wakeup sources are
disabled — stock kernel/ACPI defaults decide what can wake the machine.

One trade-off: because the RTC alarm causes a real, brief S3 resume before
the hook re-triggers hibernate, there can be a momentary screen/keyboard
light flicker on the timer-driven hibernate path that `suspend-then-hibernate`
didn't have, since that mechanism transitioned straight from suspend to
hibernate inside one systemd sleep transaction.

### `hibernate-trigger` logging

The `hibernate-trigger` system-sleep hook logs every cycle under that tag,
since both `HandleLidSwitch` and `IdleAction` route through stock
`systemd-suspend.service`. Check the outcome of any cycle with:

```bash
journalctl -t hibernate-trigger
```

Each cycle logs the wakealarm arming time on suspend, and on resume, the
elapsed time and whether hibernate was triggered. If hibernate is ever
skipped unexpectedly, or a spurious wake reappears, this is the first thing
to check, alongside `journalctl -k -b -1` for the wake cause.

### Why the idle inhibitor is needed

logind's `IdleAction = suspend-then-hibernate` fires for any session that goes idle, including logged-in user sessions. The `logind-idle-inhibitor` systemd user service holds a logind `idle` inhibitor while the user is active, preventing the 30 s GDM timer from also firing during desktop use. GNOME's own power plugin handles user-session sleep instead.

### Why `gdm.autoSuspend = false` and GDM screensaver disabled

GDM runs its own GNOME session. `gdm.autoSuspend = false` sets `sleep-inactive-*-type = 'nothing'` in the GDM dconf profile so GDM's power plugin never initiates a system sleep. The GDM dconf profile also sets `idle-delay = 0` (never idle) and disables `lock-enabled` and `idle-activation-enabled` so the GDM screen shield never activates due to accumulated idle time on resume.

### Manual hibernate from an active session is known-broken

`systemctl hibernate` (or any sleep operation) invoked while the desktop is active and unlocked will resume with the lock screen briefly visible and then dark until you press a key. Root cause: gsd-power and mutter don't finish their pre-suspend state transitions in the ~5 s before the kernel suspends, so the resume image carries a partially-transitioned display state.

The natural path — let the system idle until `IdleAction` fires `suspend-then-hibernate` — does not have this problem, because the long idle/blank/lock chain fully settles all display state before suspend. Use that for normal hibernation. If you need to hibernate immediately from an active session and want a clean resume, run `loginctl lock-session && sleep 45 && systemctl hibernate` — the 45 s gives the same settling time the natural path gets implicitly.

A system-sleep hook to enforce this from inside `systemd-hibernate.service` was investigated and dropped: it would have to either accept a visible pre-sleep flash on every manual hibernate (since the only available locking mechanism renders the lock screen visibly) or invoke significant additional engineering (patched gsd-power, mutter D-Bus extensions, or a DRM-ioctl helper). Neither tradeoff justified the cost for a rarely-used path.

## Verification

```bash
# Verify hibernate works end-to-end
systemctl hibernate

# Check the hibernate-trigger hook is installed
ls -l /etc/systemd/system-sleep/hibernate-trigger

# Check logind configuration
loginctl show-session | grep -i idle

# Check the idle inhibitor is running in a user session
systemctl --user status logind-idle-inhibitor

# Check which inhibitors are currently held
systemd-inhibit --list
```
