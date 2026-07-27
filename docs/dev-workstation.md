# Development Workstation

The development toolchain and hardware access a workstation needs — `roles/dev/`
plus the system modules that back it.

This is the layer that needs *host-level* support to work: a container runtime,
udev rules for debug hardware, a `/bin/bash` shim. Desktop applications and
appearance are [docs/desktop.md](desktop.md); the layering rule itself is
[docs/architecture.md § Placement Rule](architecture.md#placement-rule).

## What `roles/dev/` Provides

| File | Provides |
| --- | --- |
| `roles/dev/containers.nix` | Podman with a `docker` shim, tuned for devcontainers |
| `roles/dev/tools.nix` | Connect IQ SDK manager and a JDK; enables `custom.binCompat` |
| `roles/dev/network-tools.nix` | `dnsutils` — `dig`/`nslookup`/`host` |

`network-tools.nix` exists because `dig` can query a specific resolver and port
directly (`dig @127.0.0.1 -p 5335` against unbound on `defiant`), which `curl`
and `getent` cannot do.

## Containers

`roles/dev/containers.nix` runs Podman with `dockerCompat`, so tooling that
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

`roles/dev/tools.nix` installs `connect-iq-sdk-manager` (a non-interactive Go CLI
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
