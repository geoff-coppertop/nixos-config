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
| `hosts/enterprise-d/power.nix` | logind lid/key actions, `IdleAction` for GDM, `HibernateDelaySec` |
| `roles/desktop/gnome.nix` | `logind-idle-inhibitor` user service — blocks logind `IdleAction` during user sessions so GNOME manages sleep instead |
| `users/thomasga/gnome.nix` | GNOME idle/sleep dconf settings: screen blank at 4 min, battery sleep at 5 min, lock on blank, critical battery hibernate |

### Why the idle inhibitor is needed

logind's `IdleAction = suspend-then-hibernate` fires for any session that goes idle, including logged-in user sessions. The `logind-idle-inhibitor` systemd user service holds a logind `idle` inhibitor while the user is active, preventing the 30 s GDM timer from also firing during desktop use. GNOME's own power plugin handles user-session sleep instead.

### Why `gdm.autoSuspend = false`

GDM runs its own GNOME session. Without this flag, GDM's power plugin fires its own sleep timer on resume — the system briefly shows the login screen then immediately blanks again, requiring a second button press. Disabling GDM's own power management and relying on logind's `IdleAction` avoids this because logind correctly resets its timer on resume.

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
