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
2. **Collect the SSH host public key** and add it to `lib/ssh-hosts.nix` (see [docs/secrets.md](../../docs/secrets.md#collect-and-pin-the-host-key-after-deploy))
3. **Generate and install your SSH login credentials** (see [docs/secrets.md](../../docs/secrets.md#generate-ssh-login-credentials))
4. **Test hibernation** (see [Verification](#verification))
5. **Validate the system** (see [docs/operations.md](../../docs/operations.md#validation-commands))

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

On battery, sustained idle always wins: logind's `IdleAction` suspends at ~4.5 min when nothing inhibits, and the `battery-idle-suspend` watchdog forces `systemctl suspend -i` at 5 min if an application (e.g. a Firefox tab "Playing video") holds a suspend inhibitor that would otherwise block it indefinitely. The forced suspend relies on a polkit rule granting root the `suspend-ignore-inhibit` action non-interactively (the watchdog is a system service with no auth agent). The watchdog logs every countdown transition under `journalctl -t battery-idle-suspend`: countdown started, countdown reset (with the reason — back on AC, no active session, session active again, remote session active), and the forced suspend itself. Steady-state runs where nothing was in progress stay silent.

Two refinements to "idle wins": *foreground* media playback holds an idle inhibit on the visible surface, so the session never reads idle and no countdown starts — watching a movie is activity, and critical-battery hibernate backstops the walked-away case. And **active SSH sessions count as activity**: the `remote-session-idle-inhibitor` service blocks logind's `IdleAction` while a remote login exists, and the watchdog independently skips its forced suspend for the same reason (it ignores inhibitors by design, so it needs its own check).

### GDM login screen (no user logged in)

Behaviour is identical on AC and battery — there are no running user processes to protect.

| Trigger | Action |
| --- | --- |
| ~60–90 s at the login screen | Suspend, hibernate after 10 min |
| 10 min suspended | Hibernate |

The greeter's own compositor cannot report idle — the GDM dconf profile sets `idle-delay=0` to fix resume blanking, which disables its idle tracking entirely. Instead, the system-level `greeter-idle-hint` timer (30 s tick) marks any *active* greeter-class session idle via logind `SetIdleHint`, and logind's `IdleActionSec=30` suspends ~30 s after that. Net: suspend lands ~60–90 s after the login screen appears, never earlier than logind's 60 s holdoff after boot/resume. The mechanism is display-manager-agnostic (`greeter` is a logind session class, not a GDM concept) and logs under `journalctl -t greeter-idle-hint`. Caveat: the manual hint doesn't clear on greeter keystrokes, so standing at the login screen for over a minute without logging in can suspend mid-entry — accepted, matching the old "screen is unattended in practice" assumption.

## Resuming

- **From suspend (s2idle):** open the lid or press the power button.
- **From hibernate:** press the power button. Opening the lid does not resume from hibernate — this is a Framework EC firmware limitation with no Linux-side workaround.

## Implementation

| File | Responsibility |
| --- | --- |
| `hosts/enterprise-d/power.nix` | logind lid/key actions, `IdleAction`, RTC wakeup kernel param, `hibernate-trigger` system-sleep hook (arms RTC wakealarm, decides hibernate on resume, logging), a preflight on `hibernate-trigger-hibernate` that diagnoses (and, for a known `memfd_secret()` cause, auto-remediates) a kernel-level hibernate block before every attempt, `hibernate-trigger-fallback` (re-suspends on a failed hibernate so the RTC cycle retries instead of draining awake), build-time assertions that `resumeDevice` matches a configured swap device |
| `profiles/desktop/power.nix` | UPower critical-battery hibernate; `idle-hint` user service (swayidle sets logind `IdleHint` on `ext-idle-notify-v1` compositors, skipped on GNOME/gdm, start-limited so an unsupported compositor fails visibly); `greeter-idle-hint` system timer (marks an active greeter-class session idle so the login screen can suspend); `logind-idle-inhibitor` user service (blocks logind `IdleAction` only while on AC, skipped for gdm); `remote-session-idle-inhibitor` (SSH counts as activity) and the `battery-idle-suspend` watchdog (forces `suspend -i` on battery past 5 min idle, overriding application inhibitors, via a root polkit grant; skips when a remote session is active); shared Mains-only AC-detection and remote-session helpers |
| `users/thomasga/gnome.nix` | GNOME-side dconf only: screen blank at 4 min (which is also when Mutter sets logind `IdleHint` — the suspend chain's trigger), lock on blank, gsd-power disabled from sleeping the system |

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
elapsed time and whether hibernate was triggered. The pre-suspend side
clears any leftover alarm, verifies the new arm succeeded, and records the
outcome in the state file; a failed arm is logged loudly (`FAILED to arm
wakealarm`) and the resume side then refuses the hibernate decision for
that cycle — otherwise a much-later user wake would be misread as the
timer firing and hibernate the machine mid-resume. If the hibernate itself
fails, `hibernate-trigger-fallback` logs `hibernate FAILED, re-suspending`
under the same tag and re-suspends, re-arming the RTC cycle — a failed
hibernate retries every ~10 min from sleep instead of draining awake. If
hibernate is ever skipped unexpectedly, or a spurious wake reappears, this
is the first thing to check, alongside `journalctl -k -b -1` for the wake
cause.

### Hibernate preflight: `hibernate-trigger-diag`

Before every RTC-triggered hibernate attempt, an `ExecStartPre` on
`hibernate-trigger-hibernate.service` checks whether the kernel currently
supports hibernation at all (`grep disk /sys/power/state` — this reflects
`hibernation_available()` in `kernel/power/hibernate.c`, which is false if
`nohibernate` is set, kernel lockdown is active, a CXL device is present, or
any process holds a `memfd_secret()` mapping). If hibernation is
unavailable, everything that decision depends on — `/sys/power/state`,
`/sys/power/resume`, `swapon --show`, held inhibitors
(`systemd-inhibit --list`), and lockdown status — is logged in one line
under `hibernate-trigger-diag`:

```bash
journalctl -t hibernate-trigger-diag
```

One specific cause gets auto-remediated: a process holding a
`memfd_secret()` mapping blocks hibernation system-wide, for every process,
for as long as it runs (`secretmem_active()` in `mm/secretmem.c` is a
global, not per-process, gate). Backgrounded Electron/Chromium apps have
been observed doing this opportunistically (Bitwarden's V8 sandbox is the
one seen here so far) with no user-visible symptom other than hibernate
silently never succeeding. The preflight finds any such process via
`/proc/*/maps`, closes it (`SIGTERM`, then `SIGKILL` after 2s if still
alive), and retries. Whether or not that fixes it, a desktop notification
fires either way ("Closed an app so the system could hibernate" or "Hibernate
is blocked and couldn't be resolved automatically"), pointing at
`journalctl -t hibernate-trigger-diag` for detail — so a hibernate-blocking
issue is discovered within the hour it happens, not weeks of silent
retry-loop failures later.

This preflight never fails the service itself — every branch exits 0 — so a
preflight bug can't get in the way of the actual hibernate attempt or its
existing `hibernate-trigger-fallback` retry path.

### DE independence

Suspend/hibernate policy lives entirely at the systemd/logind/UPower layer, so it survives swapping GNOME/GDM for another desktop (COSMIC, Hyprland, …):

- **logind** owns lid actions, idle suspend (`IdleAction`), and — via the `hibernate-trigger` hook — the suspend→hibernate chain (`hosts/enterprise-d/power.nix`).
- **UPower** owns critical-battery hibernate (`criticalPowerAction = "Hibernate"` at 2%, `profiles/desktop/power.nix`). The upower daemon performs the action itself; no DE involvement.
- The one thing the active session must provide: set the logind session `IdleHint` at ~240 s of inactivity — that hint is what `IdleAction` and the `battery-idle-suspend` watchdog key off. GNOME/Mutter sets it natively at `idle-delay`. Any compositor implementing `ext-idle-notify-v1` (COSMIC, Hyprland, sway) is covered by the `idle-hint` swayidle user service, which skips itself on GNOME (Mutter doesn't speak that protocol).
- Greeter sessions get the hint from the system instead: the `greeter-idle-hint` timer marks any active greeter-class session idle after ~30 s, since login-screen compositors either disable idle tracking (GDM here, deliberately) or can't be relied on for it. `greeter` is a logind session class, so this covers any display manager's login screen unchanged.

Requirements for a replacement DE:

1. Its session must reach `graphical-session.target` in the systemd user manager (GNOME and COSMIC do; Hyprland needs its uwsm/systemd session variant), so the `idle-hint` and `logind-idle-inhibitor` services start.
2. Its own power manager must be told not to sleep the system, so it never races logind — the GNOME equivalent is the `sleep-inactive-*` keys in `users/thomasga/gnome.nix`.
3. Screen blank/lock timing stays a per-DE concern; only the `IdleHint` timing (240 s) needs to be kept consistent.

### Why the idle inhibitor is needed

logind's `IdleAction = suspend` fires for any session that goes idle, including logged-in user sessions. The `logind-idle-inhibitor` systemd user service holds a logind `idle` inhibitor while on AC, implementing the "on AC, never sleep" half of the policy; on battery no inhibitor is held and `IdleAction` fires ~30 s after the session sets `IdleHint`.

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
