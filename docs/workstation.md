# Workstation Capability

What a workstation-class machine provides: a graphical environment
(`profiles/desktop/`) and a development toolchain (`profiles/dev/`), plus the system
modules backing them.

This is machine capability, not personal preference — it is what the host *can
do*, decided when the machine is defined. `hosts/reliant/configuration.nix` not
importing `profiles/desktop` is that decision in action. A person's own settings on
top — theme, wallpaper, which optional apps they install — are
[docs/desktop.md](desktop.md). The layering rule is
[docs/architecture.md § Placement Rule](architecture.md#placement-rule).

## What `profiles/desktop/` Provides

| File | Provides |
| --- | --- |
| `profiles/desktop/gnome.nix` | GNOME, GDM, system-wide dconf, and pruning of unwanted default applications — active only when `custom.desktop.environment = "gnome"` (declared in `modules/desktop.nix`) |
| `profiles/desktop/printing.nix` | CUPS printing — DE-independent, always on |
| `profiles/desktop/audio.nix` | pipewire with ALSA/Pulse compatibility and rtkit |
| `profiles/desktop/power.nix` | logind idle/suspend policy, UPower critical-battery hibernate, AC and remote-session detection |

Pruning default desktop applications belongs here, not in per-user config —
typical candidates are a tour app, a help viewer, bundled games.

`profiles/desktop/gnome.nix` also installs two GNOME Shell extensions absent
from nixpkgs, each packaged as its own derivation in `pkgs/` (`fetchFromGitHub`
pinned to a rev, `glib-compile-schemas`, installed to
`$out/share/gnome-shell/extensions/<uuid>/`) rather than referenced as
`pkgs.gnomeExtensions.*`:

- `pkgs/search-light.nix` — an app-search launcher.
- `pkgs/eepresetselector.nix` — a top-panel menu to switch EasyEffects
  presets, uuid `eepresetselector@ulville.github.io`. Complements the
  EasyEffects EQ presets in `users/thomasga/easyeffects.nix`; enabling the
  extension itself and its keybindings is per-user (`docs/desktop.md`), same
  split as every other extension here — this profile only makes the package
  available.

`profiles/desktop/power.nix` is one half of this machine's suspend/hibernate
design; the other half is `hosts/<machine>/power.nix`. They are documented
together as a single table in
[hosts/enterprise-d/README.md](../hosts/enterprise-d/README.md) — read both
before changing either.

## What `profiles/dev/` Provides

| File | Provides |
| --- | --- |
| `profiles/dev/containers.nix` | Podman with a `docker` shim, tuned for devcontainers |
| `profiles/dev/tools.nix` | Connect IQ SDK manager and a JDK; enables `custom.binCompat` |
| `profiles/dev/network-tools.nix` | `dnsutils` — `dig`/`nslookup`/`host` |

`network-tools.nix` exists because `dig` can query a specific resolver and port
directly (`dig @127.0.0.1 -p 5335` against unbound on `reliant`), which `curl`
and `getent` cannot do.

## Containers

`profiles/dev/containers.nix` runs Podman with `dockerCompat`, so tooling that
shells out to `docker` — notably the VS Code devcontainer CLI — works
unmodified. Four settings there are load-bearing and were each set against a
real failure:

- **`slirp4netns` instead of pasta for rootless networking.** Podman 5.0 made
  pasta the rootless default. Pasta clones the host's primary outbound interface
  into the container netns, which breaks on dual-homed hosts (here Wi-Fi plus
  USB-C ethernet on the same `/24`): NetworkManager installs the kernel prefix
  route on only one interface, the container sees the other in isolation, and
  ends up with no reachable gateway. `slirp4netns` NATs through a private subnet
  and is host-config-agnostic. This needs both `extraPackages` and
  `network.default_rootless_network_cmd` — the package alone does nothing.
- **`localhost` first in `registries.search`.** Podman must resolve
  locally-built images (tagged `localhost/<name>`) before querying external
  registries. Without it, the devcontainer `updateRemoteUserUID` build step
  triggers Podman's interactive short-name disambiguation prompt, because it
  passes a bare image name in its `FROM` that matches no local image exactly.
- **`short-name-mode = "disabled"`.** Stops Podman prompting at all; it tries
  each registry in order and takes the first match.
- **`engine.image_default_format = "docker"`.** The devcontainer CLI's
  `updateRemoteUserUID` Dockerfile uses the `SHELL` instruction, which the OCI
  format does not support and silently ignores with a warning.

## Connect IQ SDK (Garmin)

`profiles/dev/tools.nix` installs `connect-iq-sdk-manager` (a non-interactive Go CLI
replacement for Garmin's broken Electron/webkit2gtk SDK Manager GUI —
[lindell/connect-iq-sdk-manager-cli](https://github.com/lindell/connect-iq-sdk-manager-cli))
and a JDK, since the SDK's `monkeyc` compiler is a Java app.

Three things are automated so a fresh machine needs no interactive setup:

- `users/thomasga/connect-iq.nix` creates `~/.Garmin/ConnectIQ/Sdks` and accepts
  Garmin's SDK license agreement on first home-manager activation.
- `users/thomasga/shell.nix` adds the currently selected SDK's `bin/` to `PATH` on
  fish startup, so `monkeyc` is available without a manual export and stays
  correct across `sdk set <version>` switches.
- `modules/bin-compat.nix` (`custom.binCompat.enable`) symlinks `/bin/bash`, which
  `monkeyc`'s shebang expects and NixOS does not provide by default.

Manage SDK versions and devices with:

```bash
connect-iq-sdk-manager sdk list
connect-iq-sdk-manager sdk download <version>
connect-iq-sdk-manager sdk set <version>
connect-iq-sdk-manager device download
```

## Plymouth Boot Theme

`enterprise-d` is currently the only host with a Plymouth theme configured.
Its `boot.plymouth.*` settings and the packaged theme
(`hosts/enterprise-d/framework-penguin-plymouth.nix`) are documented in
[hosts/enterprise-d/README.md § Boot Theme](../hosts/enterprise-d/README.md#boot-theme)
rather than here — it is Framework-laptop-specific, not a shared
`profiles/desktop/` capability, per
[docs/architecture.md § Placement Rule](architecture.md#placement-rule).

## Bambu Lab Printer Discovery (SSDP)

`custom.bambuSlicer.enable` (`modules/bambu-slicer.nix`) opens inbound UDP 2021 on the discovering host — what OrcaSlicer/Bambu Studio use to find Bambu Lab printers via SSDP, Bambuddy's virtual printer on `reliant` included. Confirmed against [ClusterM/open-bamboo-networking#89](https://github.com/ClusterM/open-bamboo-networking/issues/89) and the Bambu Lab wiki's port table.

## USB Debug Probes (udev)

`custom.debugProbes.enable` (`modules/debug-probes.nix`) installs udev rules for common USB JTAG/SWD probes — ST-Link, J-Link, FTDI-based adapters, and CMSIS-DAP devices including the Raspberry Pi Debug Probe. The rules are `modules/udev-rules/69-probe-rs.rules`, a verbatim copy of the [probe-rs](https://probe.rs/)/OpenOCD rules (also kept in `helicopter-collective`'s `.devcontainer/`), loaded via `services.udev.packages`, not `extraRules`. The module also creates the `plugdev` group (the rules' `GROUP="plugdev"` fallback); `thomasga` joins it in `hosts/enterprise-d/configuration.nix`.

The rules file is embedded via `lib/local-file.nix`, not a bare path interpolation — see [docs/architecture.md § Local Files As Build Inputs](architecture.md#local-files-as-build-inputs). Any new static asset under `profiles/dev/` or `profiles/desktop/` (another udev rule, a config file copied into a builder) needs the same treatment.

### Why `services.udev.packages` and not `extraRules`

Rule files here are named `69-*` so they sort before systemd's `70-uaccess.rules`/`73-seat-late.rules`, which only queue the `uaccess` ACL builtin if a device is already `TAG=="uaccess"` when they run; udev evaluates rule files in one pass sorted by filename. `services.udev.extraRules` merges into a single `99-local.rules`, which sorts after 73 and silently drops the ACL grant on a device's first-ever enumeration. `services.udev.packages` keeps each file's own name in `/etc/udev/rules.d/`.

Re-triggering an already-enumerated device "fixes" it because the tag persists in its udev database entry, so the bug looks like an intermittent race rather than a deterministic ordering error.

### Why the rules must live on the host

Devcontainers (e.g. `helicopter-collective`) bind-mount the host's `/dev/bus/usb` and use `--userns=keep-id`, so the kernel checks the host's device node against the host UID: whatever host udev grants `thomasga` (`plugdev`, the `TAG+="uaccess"` ACL) is what the container gets, and the image cannot grant it. With the ordering fixed, `nixos-rebuild switch` plus a normal plug-in is enough — no `udevadm trigger` or replug.

## EdgeTX Radio Flashing (udev)

`custom.edgetx.enable` (`modules/edgetx.nix`) installs `dfu-util` and `expresslrs-configurator` and loads `modules/udev-rules/69-edgetx.rules`, which grants the logged-in user access via `TAG+="uaccess"` only (no `plugdev`/`dialout` membership) to:

- STM32 DFU bootloader `0483:df11` — `dfu-util`, EdgeTX Buddy (WebUSB), Companion.
- EdgeTX USB-VCP `0483:5740` — ExpressLRS flashing through EdgeTX passthrough.
- CP210x `10c4:ea60` — the RadioMaster ELRS UART flasher dongle. This ID is inferred from the dongle's documented cp2102 driver, not read from hardware; confirm with `lsusb` when it is plugged in.

The two tty rules also set `ID_MM_DEVICE_IGNORE` so ModemManager leaves them alone. It uses `services.udev.packages` for the [reason above](#why-servicesudevpackages-and-not-extrarules). The update workflow itself lives in [geoff-coppertop/mt12-config](https://github.com/geoff-coppertop/mt12-config) (`uv run tools/card.py update`).
