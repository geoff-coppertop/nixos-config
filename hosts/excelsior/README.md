# excelsior

Headless bare-metal server running a DCS World dedicated server via the
[Aterfax container](https://github.com/Aterfax/DCS-World-Dedicated-Server-Docker)
under podman, a separate DCS-SRS voice server container, and a second,
independent unbound + AdGuard Home DNS instance alongside reliant's.

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
- `security.sudo.wheelNeedsPassword = false`, same reasoning as reliant: the
  authorized-key check is the real access gate, and a sudo password on top of
  it only blocks unattended `nixos-rebuild --target-host` deploys.
- `excelsior` alone isn't resolvable — use the mDNS `.local` name:

  ```bash
  nixos-rebuild switch --flake .#excelsior --target-host thomasga@excelsior.local --sudo
  ```

## Services And URLs

| Service | URL | Port behind Traefik |
| --- | --- | --- |
| AdGuard Home | `https://dns2.coppertop.ca` (proxied cross-host through reliant's Traefik — excelsior runs no Traefik of its own) | 3000 |
| DCS start/stop control | `https://dcs.coppertop.ca` (no auth yet — same source-IP-only posture as the rows below, pending a holistic Traefik auth pass) | 9090 (page), 9091 (webhook) |

| Port | Protocol | Purpose | Exposure |
| --- | --- | --- | --- |
| 10308 | tcp+udp | DCS game traffic | LAN/WAN (firewall open; needs a router port-forward for real remote play — see Known Gotchas) |
| 8088 | tcp | DCS's own remote-control WebGUI backend | LAN/WAN (firewall open; needs a router port-forward — DCS's own remote-control mechanism, not usable through Traefik/any reverse proxy — see Known Gotchas) |
| 5002 | tcp+udp | DCS-SRS voice (separate `dcs-srs-server` container) | LAN/WAN (firewall open) |
| 8080 | tcp | SRS REST API (`custom.dcsServer.srs.restApi.enable`, off by default) | LAN/WAN (firewall open) |
| 3000 | tcp | AdGuard Home admin UI | reliant only (firewall-restricted; proxied at `dns2.coppertop.ca`) |
| 53 | udp | DNS (AdGuard → unbound) | LAN/WAN (firewall open) |
| 5335 | tcp+udp | unbound bypass (skips AdGuard filtering) | LAN/WAN (firewall open) |
| 3001 | tcp | DCS webtop web desktop | 127.0.0.1 only |
| 9090 | tcp | DCS start/stop control page (`custom.dcsServer.control`) | reliant only (firewall-restricted; proxied at `dcs.coppertop.ca`) |
| 9091 | tcp | DCS start/stop webhook (`custom.dcsServer.control`) | reliant only (firewall-restricted; proxied at `dcs.coppertop.ca`) |

AdGuard's admin UI (3000) and `custom.dcsServer.control.bindAddress`
(9090/9091) are bound to this host's real LAN IP instead of `127.0.0.1`,
and restricted to `reliant`'s IP by `networking.firewall.extraCommands` —
neither has real auth of its own at any layer yet, so the firewall is the
only gate for both. Real Traefik auth in front of them is a deliberate
follow-up, not yet done. `custom.dcsServer.webGuiBindAddress` (8088) is
different: it's bound to the LAN IP and opened broadly (not
`reliant`-restricted) because it's meant to be reached directly by a
router WAN port-forward, not by Traefik — see Known Gotchas. See
`docs/homelab-network.md` § DCS On-Demand Start/Stop And Remote Control
(excelsior) and § Second DNS Instance (excelsior).

**`custom.dcsServer.startAtBoot = false;`** — behavior change: DCS no
longer comes up automatically after a reboot. Start it via
`https://dcs.coppertop.ca`. Stopping is manual only, by design — no
idle-timeout auto-stop.

The webtop desktop (3001) stays loopback-only — reach it through an SSH
tunnel:

```bash
ssh -L 3001:localhost:3001 thomasga@excelsior.local
```

Then open `http://localhost:3001` (web desktop) for DCS's own local WebGUI
and launcher — see Known Gotchas for why this is the only way to actually
use DCS's WebGUI (remote access via any reverse proxy doesn't work, by
DCS's own design).

## First-Time Service Setup

| Service | Action |
| --- | --- |
| DCS World | Wait for `DCSAUTOINSTALL` to finish (tens of GB), open the launcher in the tunneled web desktop, log in with Eagle Dynamics credentials, tick "save login" + auto-login |
| DCS-SRS | No manual step — separate `dcs-srs-server` container starts on its own |
| AdGuard Home | Complete the setup wizard; set upstream DNS to `127.0.0.1:5335` (same as reliant) |

After DCS login is saved, set `custom.dcsServer.autoStart = true;` and
rebuild so the DCS server launches with the container.

Starting the container (whether via the control page or manually) does
**not** by itself load a mission — DCS's own log
(`Saved Games/DCS.dcs_serverrelease/Logs/dcs.log`) will show
`Mission list is empty, server not started.` until one is configured in
`serverSettings.lua` or loaded through the WebGUI/webtop. That's separate,
unrelated setup, not something start/stop fixes.

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
out both `192.168.20.15` (reliant) and `192.168.1.10` (excelsior) as DNS
servers — that's a router-side step, not managed by this repo.

## Known Gotchas

- **`custom.dcsServer.desktopPort` is overridden to 3001.** The module
  default (3000) collides with AdGuard Home's admin UI, which also defaults
  to 3000 and is what reliant's `dns2.coppertop.ca` Traefik route depends on
  — same class of conflict reliant hit and fixed for `zwave-js`.
- **DCS-SRS is not bundled with the Aterfax DCS image.**
  [Aterfax#74](https://github.com/Aterfax/DCS-World-Dedicated-Server-Docker/issues/74)
  tracks that as unimplemented. `custom.dcsServer.srs.enable` runs the
  separate, actively maintained `jaycadi/dcs-srs-server` image as its own
  podman container instead — no Wine/.NET install needed inside the DCS
  desktop.
- **`custom.dns.lanSubnet` is overridden to `192.168.0.0/16`.** The module
  default (`192.168.1.0/24`) and reliant's own override
  (`192.168.20.0/24`) each only cover one of the network's 3 VLANs. Widened
  on both hosts so unbound's `access-control` allows direct bypass queries
  on port 5335 from any of them.
- **DCS's own remote-control WebGUI cannot be reverse-proxied for remote
  use — confirmed live, this is deliberate on DCS's part, not a bug to
  work around.** Its API backend (`custom.dcsServer.webGuiPort`, 8088,
  `POST /encryptedRequest` served by `DCS_server.exe` itself) is not a
  browsable page — `GET /` returns a bare 404 by design; the real client
  is a local HTML file (`WebGui/index.html`) shipped inside the DCS
  install, opened from the controlling PC's own filesystem, whose
  `app.js` hardcodes `http://127.0.0.1:8088` for its API calls. A same-
  origin nginx proxy (`custom.dcsServer.webGuiProxy`, since removed) was
  built to serve those static files at `dcs.coppertop.ca` with a same-
  origin `app.js` patch (a verified 3-part text patch from DCS forum
  topic
  [378083](https://forum.dcs.world/topic/378083-webgui-over-reverse-proxy-invalid-url-for-encryptedrequest/),
  reapplied via a self-healing `systemd.path` unit since DCS's own
  auto-updater periodically overwrites the file). It correctly served the
  real dashboard UI — but every `/encryptedRequest` call still failed,
  confirmed live across four independent fixes, each disproven in turn:
  binding the raw backend to loopback instead of the LAN IP (still
  failed, `invalid PKCS #7 block padding` in `dcs.log`); forcing the
  client's `credentials: "omit"` to match the working local path (changed
  the failure mode to a clean `422 Unprocessable Entity` — DCS's own
  documented rejection code, "remote non-locally-originating requests
  refused unless a key was negotiated with the DCS master server"); and
  overriding the proxied request's `Host` header to `127.0.0.1` (still
  422). Web research beyond DCS's own forums confirmed this in plain
  terms: "This client can only be used to control a local DCS_server.exe
  instance due to the encryption requirement... a deliberate security
  measure implemented by DCS to prevent remote control of servers through
  reverse proxies without proper authentication." Not an official use
  case, and not achievable this way — don't re-attempt a same-origin
  proxy for this. DCS's own log during this investigation showed the real
  intended mechanism: `Registering HTTP control interface as
  <public-ip>:8088 (port is assumed to be open)` — DCS's remote-control
  assumes a **direct WAN port-forward** to 8088 (and 10308 for the game
  itself), no HTTP-layer proxy in the path at all. `webGuiBindAddress` is
  bound to this host's LAN IP and the firewall opens 8088 broadly for
  exactly that; the router-side port-forward itself is not managed by
  this repo. For anything the WebGUI is actually needed for (loading
  missions, server settings), use the local webtop desktop instead (see
  Services And URLs above) — that's genuinely local, not proxied, and
  works today.

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
