# excelsior

Headless bare-metal server running a DCS World dedicated server via the
[Aterfax container](https://github.com/Aterfax/DCS-World-Dedicated-Server-Docker)
under podman, a separate DCS-SRS voice server container, and a second,
independent unbound + AdGuard Home DNS instance alongside defiant's.

The reusable DNS/Traefik service layer is documented in
[docs/homelab-network.md](../../docs/homelab-network.md). Provisioning steps
are the generic disko flow in
[docs/provisioning.md § Provision Types](../../docs/provisioning.md#provision-types)
onward (same as enterprise-d).

## Machine Files

| File | Purpose |
| --- | --- |
| `configuration.nix` | Boot, hardware, networking, and every `custom.*` service setting |
| `hardware.nix` | systemd-boot, EFI, Intel microcode, generic firmware |
| `disko.nix` | GPT layout: ESP, swap, btrfs root with `@`/`@home`/`@dcs` subvolumes |
| `default.nix` | home-manager attachment |
| `secrets.nix` | `age.secrets` declarations for this host |
| `home/thomasga.nix` | Per-machine home-manager profile (headless) |
| `provision-type` | `disko` |

## Hardware And Access

- HP EliteDesk 800 G2 Mini — Intel Core i5-6500T @ 3.1GHz, 16GB RAM, 1TB WD
  Blue SA510 (SATA SSD). 8GB+ RAM per DCS instance; single-thread CPU
  performance matters most; the DCS install needs 60–120GB depending on
  terrains.
- Reserved LAN IP `192.168.1.10` (main LAN, same segment as the NAS).
- Headless. `profiles/desktop` is deliberately **not** imported — there is no
  display server. `profiles/dev` is also not imported — no devcontainer
  tooling needed; `virtualisation.oci-containers` enables podman itself.
- SSH key only: `PasswordAuthentication`, `KbdInteractiveAuthentication`, and
  `PermitRootLogin` are all off.
- `security.sudo.wheelNeedsPassword = false`, same reasoning as defiant: the
  authorized-key check is the real access gate, and a sudo password on top of
  it only blocks unattended `nixos-rebuild --target-host` deploys.
- `excelsior` alone isn't resolvable — use the mDNS `.local` name:

  ```bash
  nixos-rebuild switch --flake .#excelsior --target-host thomasga@excelsior.local --sudo
  ```

## Services And URLs

| Service | URL | Port behind Traefik |
| --- | --- | --- |
| AdGuard Home | `https://dns2.coppertop.ca` (proxied cross-host through defiant's Traefik — excelsior runs no Traefik of its own) | 3000 |

| Port | Protocol | Purpose | Exposure |
| --- | --- | --- | --- |
| 10308 | tcp+udp | DCS game traffic | LAN/WAN (firewall open) |
| 5002 | tcp+udp | DCS-SRS voice (separate `dcs-srs-server` container) | LAN/WAN (firewall open) |
| 8080 | tcp | SRS REST API (`custom.dcsServer.srs.restApi.enable`, off by default) | LAN/WAN (firewall open) |
| 3000 | tcp | AdGuard Home admin UI | LAN/WAN (firewall open) |
| 53 | udp | DNS (AdGuard → unbound) | LAN/WAN (firewall open) |
| 5335 | tcp+udp | unbound bypass (skips AdGuard filtering) | LAN/WAN (firewall open) |
| 3001 | tcp | DCS webtop web desktop | 127.0.0.1 only |
| 8088 | tcp | ED remote-control WebGUI | 127.0.0.1 only |

DCS admin surfaces (webtop, WebGUI) are loopback-only — the webtop desktop
has weak default auth. Reach them through an SSH tunnel:

```bash
ssh -L 3001:localhost:3001 -L 8088:localhost:8088 thomasga@excelsior.local
```

Then open `http://localhost:3001` (web desktop) and
`http://localhost:8088` (WebGUI).

## First-Time Service Setup

| Service | Action |
| --- | --- |
| DCS World | Wait for `DCSAUTOINSTALL` to finish (tens of GB), open the launcher in the tunneled web desktop, log in with Eagle Dynamics credentials, tick "save login" + auto-login |
| DCS-SRS | No manual step — separate `dcs-srs-server` container starts on its own |
| AdGuard Home | Complete the setup wizard; set upstream DNS to `127.0.0.1:5335` (same as defiant) |

After DCS login is saved, set `custom.dcsServer.autoStart = true;` and
rebuild so the DCS server launches with the container.

## DCS Server Maintenance

**Updates are manual, not automatic** — `custom.dcsServer.autoInstall` is set
to `false` on this host, overriding the module default. Confirmed live: with
it left at the default (`true` → `DCSAUTOINSTALL=1`), `DCS_updater.exe apply`
re-runs on *every* container restart, not just the first. When there's
nothing to install, it doesn't exit quietly — it pops up a GUI "Nothing to
install" dialog that blocks indefinitely waiting for someone to click OK,
which means `AUTOSTART` never reaches `DCS_server.exe` on an unattended
restart (confirmed live: after a restart with nobody touching the web
desktop, `DCS_server.exe` was simply never running — only the stuck
updater).

To pick up a new DCS version: temporarily set `autoInstall = true;`, rebuild,
restart the container, open the tunneled web desktop, and click through the
updater dialog once. Then set it back to `false;` and rebuild again so future
restarts stay unattended.

**Re-authenticating / changing the saved login**: not documented by the
upstream Aterfax image. If you ever need to log out or switch accounts,
open the launcher through the tunneled web desktop (see above) and look
for a logout/change-account option in the launcher UI itself — there's no
known config file or CLI path for this, and guessing one wrong risks
corrupting the DCS install rather than just requiring a re-login.

## DNS Bypass

Clients needing unfiltered DNS — this skips AdGuard's ad-blocking but keeps
`coppertop.ca` resolution:

```bash
dig @excelsior.local -p 5335 example.com
```

Point a device at `192.168.1.10:5335` in its DNS settings to bypass AdGuard
permanently. For actual DNS redundancy, the router/DHCP config needs to hand
out both `192.168.20.10` (defiant) and `192.168.1.10` (excelsior) as DNS
servers — that's a router-side step, not managed by this repo.

## Known Gotchas

- **`custom.dcsServer.desktopPort` is overridden to 3001.** The module
  default (3000) collides with AdGuard Home's admin UI, which also defaults
  to 3000 and is what defiant's `dns2.coppertop.ca` Traefik route depends on
  — same class of conflict defiant hit and fixed for `zwave-js`.
- **DCS-SRS is not bundled with the Aterfax DCS image.**
  [Aterfax#74](https://github.com/Aterfax/DCS-World-Dedicated-Server-Docker/issues/74)
  tracks that as unimplemented. `custom.dcsServer.srs.enable` runs the
  separate, actively maintained `jaycadi/dcs-srs-server` image as its own
  podman container instead — no Wine/.NET install needed inside the DCS
  desktop.
- **`custom.dns.lanSubnet` is overridden to `192.168.0.0/16`.** The module
  default (`192.168.1.0/24`) and defiant's own override
  (`192.168.20.0/24`) each only cover one of the network's 3 VLANs. Widened
  on both hosts so unbound's `access-control` allows direct bypass queries
  on port 5335 from any of them.

## Provisioning

See [docs/provisioning.md](../../docs/provisioning.md) (the generic `disko`
flow, Steps 1–7) for the full enroll → install → first-boot process.
Host-specific notes:

- The LUKS passphrase prompt in `install.py` is vestigial for this host —
  disko has no LUKS here, the value is unused.
- Pin the SSH host key after first boot:
  `ssh-keyscan -t ed25519 excelsior.local` → `publicKey` in
  `lib/ssh-hosts.nix`.
- Optional follow-ups: web-desktop `PASSWORD=` as an agenix env file via
  `custom.dcsServer.environmentFiles`; `custom.backups` for
  `Saved Games/DCS.server`; router port-forwards for 10308 (+5002) if
  internet-facing.
