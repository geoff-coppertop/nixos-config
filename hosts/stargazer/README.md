# stargazer

Gaming and sim desktop: Ryzen 5800X3D, 64 GB RAM, RTX 4080 Super, 512 GB + 2 TB
NVMe, Quest 3 for VR. Linux-only (no Windows, no dual-boot).

## Machine Files

- Host entrypoint: `hosts/stargazer/configuration.nix`
- Hardware: `hosts/stargazer/hardware.nix`
- GPU (NVIDIA): `hosts/stargazer/nvidia.nix`
- Disk layout (two disks): `hosts/stargazer/disko.nix`
- Secrets (empty until provisioned): `hosts/stargazer/secrets.nix`
- Home entry: `hosts/stargazer/home/thomasga.nix`
- Flake entry: `flake.nix`

## Hardware Notes

- **GPU:** NVIDIA open kernel modules (`hardware.nvidia.open = true`) — the
  recommended path for Ada. 32-bit GL for Proton/SteamVR comes from
  `custom.gaming.enable`.
- **Disks:** disk 1 (512 GB) is NixOS root/home (LUKS → LVM → 16 GB swap + btrfs
  `@`/`@home`); disk 2 (2 TB) is the game library at `/games` (LUKS → btrfs).
  No hibernation, so swap is modest and there is no resume device.
- **Both disks are LUKS**, formatted with the same passphrase at install. Both
  auto-unlock via TPM2 once enrolled post-install — root in initrd
  (`custom.tpmLuks.enable`), the 2 TB in stage-2. Until then they prompt for the
  passphrase.

## Provisioning

Run in order on the machine after the first boot.

### 1. Enrol the host key and wire up secrets

Wi-Fi is enabled (same networks as enterprise-d, wired preferred), but the
`wifi/*.age` secrets are encrypted for enterprise-d only, so they will not
decrypt until re-keyed. The host-specific secrets (backups, network drives, SSH
login identity, GitHub token) do not exist yet — `hosts/stargazer/secrets.nix`
is an empty set. After the host key exists:

1. Enrol the host age key: `nix develop -c python3 tools/enroll.py stargazer`,
   then add its public key to `secrets/secrets.nix`.
2. Add `stargazer` to the `wifi/agt-home.age`, `wifi/agt-iot.age`, and
   `wifi/agt-work.age` recipient lists in `secrets/secrets.nix`, create the
   per-host secrets, and re-key: `nix run .#secret-rekey`.
3. Declare the host-specific secrets in `hosts/stargazer/secrets.nix` (mirror
   `hosts/enterprise-d/secrets.nix`) and enable `custom.backups` and
   `custom.networkDrives` in `configuration.nix`.
4. Collect the SSH host public key and login key — see
   [docs/ssh.md](../../docs/ssh.md) — and fill `stargazer.userPublicKeys` in
   `lib/ssh-hosts.nix`.

### 2. TPM auto-unlock and Secure Boot

Confirm the board exposes a TPM2 (fTPM in BIOS), then enrol **both** LUKS
devices — same command as enterprise-d, once per disk:

```bash
sudo systemd-cryptenroll /dev/disk/by-partlabel/root  --tpm2-device=auto --tpm2-pcrs=0,1,3,7
sudo systemd-cryptenroll /dev/disk/by-partlabel/games --tpm2-device=auto --tpm2-pcrs=0,1,3,7
```

Reboot; both should unlock with no prompt. `systemd-cryptenroll` leaves the
install passphrase in place as the fallback. If the board has no usable TPM2,
drop `custom.tpmLuks.enable` and unlock root by passphrase.

Secure Boot (`custom.secureBoot.enable`, lanzaboote) — the installer generates
keys under `/etc/secureboot`; finish enrolment per
[docs/provisioning.md § Step 6](../../docs/provisioning.md) (rebuild, enrol keys
in firmware, turn Secure Boot on in UEFI).

### 3. The 2 TB games disk

No keyfile — it uses the install passphrase and TPM (above). Once unlocking, take
ownership and add it to Steam:

```bash
sudo chown thomasga:users /games
```

Then add `/games` as a Steam library folder.

## Games

Steam + Proton covers ACC, F1 25, Le Mans Ultimate, Ghost of Tsushima, Last
Caretaker, Derail Valley, Parkitect, and Stormworks with no per-title config.
DCS is the exception below.

## DCS, VoiceAttack, VAICOM

DCS is the standalone Eagle Dynamics build; VoiceAttack is the Steam build;
VAICOM Pro is installed separately (it loads inside VoiceAttack). These live in
**separate** Wine prefixes and still work, because VAICOM talks to DCS over UDP
localhost, which crosses prefixes.

1. Run `tools/dcs-bootstrap.sh ~/Downloads/DCS_Updater.exe` — it creates DCS's
   own Proton prefix and launches the ED updater. Log in and let it download.
2. Install VoiceAttack from Steam (its own Proton prefix).
3. Install VAICOM Pro; symlink DCS's `Saved Games\DCS\Scripts` into the path it
   writes so it can drop its export hook. VAICOM↔DCS uses UDP ports
   33333/33334/33491/33492/44111.
4. VR: launch DCS through ALVR → SteamVR → OpenXR. Validate voice and VR
   together last — this stack is the fragile part and may need re-tuning after
   DCS updates.

**VoiceAttack for other games:** its network plugins (VAICOM) reach other apps
over localhost, but keypress macros only reach apps in its own prefix. Driving a
different game by keypress needs that game in VoiceAttack's prefix or a second
VoiceAttack instance.

## SimHub and SimHaptic

- **SimHub** runs under Proton; install `dotnet48` into its prefix with
  protontricks. Bass shakers (sound card) and Arduino wind-sim/dashboards work
  on Linux — the user is in the `dialout` group for serial. Telemetry is UDP.
- **SimHaptic** (bass-shaker haptics) is a Wine app like the above: UDP
  telemetry plus a DCS export hook symlinked into `Saved Games`. Route its Wine
  audio output to the bass-shaker PipeWire sink (`wpctl`/`pactl`), separate from
  the headset.

## SIMAGIC wheelbase

Force feedback is declarative — the out-of-tree `simagic-ff` module
(`custom.simagic.enable`). It requires wheelbase firmware **post-v159 /
Simpro v2**, flashed once from Windows or a USB-passthrough VM (Sim Pro Manager
needs raw USB and does not run under Wine). If Proton does not detect the base
as a wheel, hint SDL:

```bash
# find the base's VID:PID with lsusb, then, e.g.:
export SDL_JOYSTICK_WHEEL_DEVICES=0483:xxxx
```

## Discord cough button

One HOTAS button mutes **only** Discord's mic while held, so the squadron does
not hear DCS/VAICOM commands — the mic still reaches VoiceAttack (the source is
never muted). Provided by `users/thomasga/discord-cough-mute.nix`, a passive
evdev watcher (it does not grab the stick). Bind it once:

```bash
discord-cough-mute --learn      # press the button you want
systemctl --user restart discord-cough-mute
```

VoiceAttack's own PTT is bound to the same physical button inside VoiceAttack.

## Apple TV streaming

`custom.gameStreaming.enable` runs the stock nixpkgs `services.sunshine`
module unchanged. Pair from the Apple TV's Moonlight app with "Add Host
Manually".

## Build Caveats (before first `nixos-rebuild`)

`pkgs/simagic-ff.nix`'s `rev = "master"` is an unconfirmed guess at its
default branch, pinned to today's commit — a future upstream push to
`master` will hash-mismatch again (read CI's build-job failure output for the
correct SRI hash to paste in).
