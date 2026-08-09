# Workstation Capability

What a workstation-class machine provides: a graphical environment
(`profiles/desktop/`) and a development toolchain (`profiles/dev/`), plus the system
modules backing them.

This is machine capability, not personal preference — it is what the host *can
do*, decided when the machine is defined. `hosts/defiant/configuration.nix` not
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
directly (`dig @127.0.0.1 -p 5335` against unbound on `defiant`), which `curl`
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

## USB Debug Probes (udev)

`custom.debugProbes.enable` (`modules/debug-probes.nix`) installs udev rules for
common USB JTAG/SWD debug probes — ST-Link, J-Link, FTDI-based adapters, and
CMSIS-DAP compatible devices, which includes the Raspberry Pi Debug Probe. The
rules themselves live in `modules/udev-rules/69-probe-rs.rules`, a verbatim copy
of the [probe-rs](https://probe.rs/)/OpenOCD project's udev rules (the same file
is also kept in the `helicopter-collective` repo's `.devcontainer/`), and are
loaded via `services.udev.packages` — **not** `services.udev.extraRules`. The
module also creates the `plugdev` group, the rules' `GROUP="plugdev"` fallback,
and `thomasga` is a member of it via `hosts/enterprise-d/configuration.nix`.

The rules file is embedded into its builder via `lib/local-file.nix`, not a
bare `${./udev-rules/69-probe-rs.rules}` interpolation — see
[docs/architecture.md § Local Files As Build Inputs](architecture.md#local-files-as-build-inputs).
Any new static asset added under `profiles/dev/` or `profiles/desktop/`
(another udev rule, a config file copied into a builder) needs the same
treatment.

### Why `services.udev.packages` and not `extraRules`

This file's own name matters. It is called `69-probe-rs.rules` upstream
specifically so it sorts *before* systemd's own
`70-uaccess.rules`/`73-seat-late.rules`. Those files only queue the `uaccess`
ACL-granting builtin if a device is already `TAG=="uaccess"` at the point they
are evaluated, and udev processes all rule files in one linear pass sorted by
filename.

`services.udev.extraRules` merges its content into a single generated file always
named `99-local.rules`, which sorts *after* 73 — silently breaking the ACL grant
on every first-ever enumeration of a device, since our `TAG+="uaccess"`
assignment would run too late to be seen. `services.udev.packages` preserves each
file's own name in `/etc/udev/rules.d/`, restoring the intended ordering.

This bug is easy to miss because re-triggering an already-enumerated device
"fixes" it — the tag persists in that device's udev database entry from an
earlier pass — making it look like an intermittent timing race rather than a
deterministic ordering bug.

### Why the rules must live on the host

Embedded-dev devcontainers (e.g. `helicopter-collective`) do not create their own
USB device nodes. They bind-mount the host's `/dev/bus/usb` into the container
(via `devcontainer.json`'s `mounts`) and rely on `--userns=keep-id` to map the
container user to the host user's UID. Permission checks on that bind mount are
enforced by the kernel against the same device node the host owns, so whatever
the *host's* udev grants `thomasga` — through `plugdev` group membership and the
rules' `TAG+="uaccess"` ACL — is exactly what the container process gets. There is
no way to grant this access from inside the container image.

With the ordering fixed, a fresh `nixos-rebuild switch` plus a normal plug-in of
the probe is enough — no manual `udevadm trigger` or replug workaround.
