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
| 5 min idle | `suspend-then-hibernate` starts |
| 10 min suspended | Hibernate |
| Critical battery | Immediate hibernate, bypassing suspend |

### GDM login screen (no user logged in)

Behaviour is identical on AC and battery — there are no running user processes to protect.

| Trigger | Action |
| --- | --- |
| 30 s idle | `suspend-then-hibernate` starts |
| 10 min suspended | Hibernate |

The 30 s window applies from when the login screen goes idle, which itself follows GNOME's default `idle-delay`. In practice the screen is unattended from first appearance, so this fires approximately 30 s after GDM starts.

## Resuming

- **From suspend (s2idle):** open the lid or press the power button.
- **From hibernate:** press the power button. Opening the lid does not resume from hibernate — this is a Framework EC firmware limitation with no Linux-side workaround.

## Implementation

| File | Responsibility |
| --- | --- |
| `hosts/enterprise-d/power.nix` | logind lid/key actions, `IdleAction` for GDM, `HibernateDelaySec`, RTC wakeup kernel param, `hibernate-trigger` logging |
| `roles/desktop/gnome.nix` | `logind-idle-inhibitor` user service — blocks logind `IdleAction` during user sessions so GNOME manages sleep instead |
| `users/thomasga/gnome.nix` | GNOME idle/sleep dconf settings: screen blank at 4 min, battery sleep at 5 min, lock on blank, critical battery hibernate |

### Why `rtc_cmos.use_acpi_alarm=1`

`suspend-then-hibernate` previously failed to reach hibernate reliably: the
RTC alarm that wakes the machine from s2idle to trigger the hibernate
transition raced with the AMD `amd-pmc` driver's timer-based S0i3 wakeup
handling (an `rtc->aie_timer` mismatch between the kernel's HPET-based RTC
programming and the EC-routed alarm). systemd's own wake-source check would
then read the wake as user-initiated and return to the desktop instead of
proceeding to hibernate. This is a known issue on AMD laptops generally, not
specific to this hardware.

The fix is the kernel boot parameter `rtc_cmos.use_acpi_alarm=1`, which
switches RTC wakeup to ACPI alarms instead of HPET, avoiding the race at the
kernel/EC layer where it originates. This replaces an earlier, abandoned
approach (a custom-patched `systemd` binary plus several ACPI/PCI
wake-source suppressions) that regressed hibernate entirely; that approach
is not used here. No wakeup sources are disabled — stock kernel/ACPI
defaults decide what can wake the machine.

### `hibernate-trigger` logging

`systemd-suspend-then-hibernate.service` carries permanent
`ExecStartPre`/`ExecStartPost` hooks, tagged `hibernate-trigger`, since both
`HandleLidSwitch` and `IdleAction` route through this one unit. Check the
outcome of any cycle with:

```bash
journalctl -t hibernate-trigger
```

Each cycle logs a start timestamp and, on resume, whether the machine
actually went through S4 (`hibernated: yes`/`no`, derived from
`journalctl -k -b -1`). If hibernate is ever skipped or a spurious wake
reappears, this is the first thing to check, alongside `journalctl -k -b -1`
for the wake cause.

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

# Check the hibernate delay setting
cat /etc/systemd/sleep.conf.d/*.conf

# Check logind configuration
loginctl show-session | grep -i idle

# Check the idle inhibitor is running in a user session
systemctl --user status logind-idle-inhibitor

# Check which inhibitors are currently held
systemd-inhibit --list
```
