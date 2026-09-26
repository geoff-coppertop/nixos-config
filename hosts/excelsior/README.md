# excelsior

Headless bare-metal server running a DCS World dedicated server via the
[Aterfax container](https://github.com/Aterfax/DCS-World-Dedicated-Server-Docker)
under podman, a separate DCS-SRS voice server container, a native Factorio
headless dedicated server (`custom.factorioServer`, wrapping nixpkgs'
`services.factorio` — no container, unlike DCS), and a second, independent
unbound + AdGuard Home DNS instance alongside reliant's.

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

| Service | URL |
| --- | --- |
| AdGuard Home | `https://dns2.coppertop.ca` (proxied cross-host through reliant's Traefik — excelsior runs no Traefik of its own) |
| DCS webtop desktop | `https://dcs.coppertop.ca` (no auth yet — same source-IP-only posture as everything else here, pending a holistic Traefik auth pass) |
| DCS start/stop control | `https://dcs-control.coppertop.ca` (no auth yet, same source-IP-only posture as DCS webtop desktop above) |
| Jellyfin | `https://jellyfin.coppertop.ca` (proxied cross-host; its own accounts are the auth) |
| Automatic Ripping Machine | `https://rip.coppertop.ca` (proxied cross-host, gated by Authelia forward-auth on reliant; ARM's own login screen is off — `custom.autoRip.disableLogin`) |
| Factorio ("CGWANO") | in-game server browser (LAN broadcast), `excelsior.local:34197` on the LAN, or `factorio.coppertop.ca:34197` for remote friends once `custom.ddns` (see `docs/homelab-network.md` § Dynamic DNS) is applied on reliant and the router port-forwards UDP 34197 to this host — joining requires the in-game password (agenix secret, see Known Gotchas) |

### Ports

Every port this host binds, in ascending order — the complete list for
`excelsior`. Check it before assigning or moving a port here, and update it in
the same commit ([docs/architecture.md § Placement
Rule](../../docs/architecture.md#placement-rule)).

| Port | Protocol | Purpose | Exposure |
| --- | --- | --- | --- |
| 22 | tcp | SSH, `services.openssh` with `openFirewall = true` | LAN (firewall open); key-only auth, no password/root login |
| 53 | udp | DNS (AdGuard Home → unbound), `custom.dns` | LAN/WAN (firewall open; TCP 53 deliberately not opened) |
| 3000 | tcp | AdGuard Home admin UI, `custom.dns` (upstream default) | Bound `0.0.0.0`, `openFirewall = false`; reliant only (firewall-restricted to `192.168.20.15`; proxied at `dns2.coppertop.ca`) |
| 3001 | tcp | DCS webtop web desktop, `custom.dcsServer.desktopPort` — overridden from the module default (3000), which AdGuard's admin UI holds here | Bound to `192.168.1.10` (`desktopBindAddress`); reliant only (firewall-restricted); proxied at `dcs.coppertop.ca` |
| 5002 | tcp+udp | DCS-SRS voice (separate `dcs-srs-server` container), `custom.dcsServer.srs.port` | LAN/WAN (firewall open) |
| 5335 | tcp+udp | unbound bypass (skips AdGuard filtering), `custom.dns` | LAN/WAN (firewall open) |
| 5353 | udp | avahi/mDNS, `profiles/common/networking.nix` (`openFirewall = true`) | LAN (firewall open) — what makes `excelsior.local` resolve for deploys |
| 8080 | tcp | Automatic Ripping Machine web UI, `custom.autoRip.webPort` | Bound `0.0.0.0`, `openFirewall = false`; reliant only (firewall-restricted; proxied at `rip.coppertop.ca`) |
| 8080 | tcp | SRS REST API, `custom.dcsServer.srs.restApi.port` (`restApi.enable` off) | **Not bound today** — and its default is the 8080 `custom.autoRip.webPort` already holds above. Nothing asserts on this pair; move one of the two before enabling the REST API |
| 8088 | tcp | DCS's own remote-control WebGUI backend, `custom.dcsServer.webGuiPort` | Bound to `192.168.1.10` and opened broadly — meant to be reached by a router WAN port-forward, not usable through Traefik/any reverse proxy (see Known Gotchas) |
| 8096 | tcp | Jellyfin, `custom.jellyfin` with `openFirewall = false` | reliant only (firewall-restricted; proxied at `jellyfin.coppertop.ca`) |
| 8920 (tcp), 1900 + 7359 (udp) | tcp/udp | Jellyfin's other ports — nixpkgs' `services.jellyfin` opens four ports, not just 8096 | **Not opened today** — `custom.jellyfin.openFirewall = false` here; setting it true opens these three alongside 8096 |
| 9090 | tcp | DCS start/stop control page (nginx), `custom.dcsServer.control.pagePort` | Bound to `192.168.1.10`; reliant only (firewall-restricted; proxied at `dcs-control.coppertop.ca`) |
| 9091 | tcp | DCS start/stop/status/mission-upload webhook, `custom.dcsServer.control.webhookPort` | Same as 9090 (proxied at `dcs-control.coppertop.ca/hooks`) |
| 10308 | tcp+udp | DCS game traffic, `custom.dcsServer.gamePort` | LAN/WAN (firewall open; needs a router port-forward for real remote play, then remote friends connect at `dcs.coppertop.ca:10308` — via `custom.ddns` on reliant; see Known Gotchas) |
| 10309 | tcp+udp | DCS in-game VoIP, `custom.dcsServer.voiceChat.port` (`voiceChat.enable` off) | **Not bound today** — free, no collision if it is switched on |
| 34197 | udp | Factorio game traffic, `custom.factorioServer` via `services.factorio.openFirewall` | LAN/WAN (firewall open; same port-forward story as 10308, at `factorio.coppertop.ca:34197`) |

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
`https://dcs-control.coppertop.ca`. Stopping is manual only, by design — no
idle-timeout auto-stop.

The webtop desktop is reachable at `https://dcs.coppertop.ca` —
unlike DCS's own WebGUI API, webtop is just a noVNC session, so proxying it
cross-host works fine (see `docs/homelab-network.md` § DCS's webtop desktop
is proxied cross-host). An SSH tunnel still works too, if you'd rather not
rely on the no-auth proxy:

```bash
ssh -L 3001:localhost:3001 thomasga@excelsior.local
```

Then open `http://localhost:3001` (or the `dcs.coppertop.ca` URL
above) for DCS's own local WebGUI and launcher — see Known Gotchas for why
this in-desktop access is the only way to actually use DCS's WebGUI itself
(remote access to *that* via any reverse proxy doesn't work, by DCS's own
design — the desktop being proxied doesn't change that). `dcs-control.coppertop.ca`
itself now also has a mission upload form — no tunnel needed just to get a
`.miz` file onto the host — see `docs/homelab-network.md` § DCS On-Demand
Start/Stop And Remote Control.

## First-Time Service Setup

| Service | Action |
| --- | --- |
| DCS World | Wait for `DCSAUTOINSTALL` to finish (tens of GB), open the launcher in the tunneled web desktop, log in with Eagle Dynamics credentials, tick "save login" + auto-login |
| DCS-SRS | No manual step — separate `dcs-srs-server` container starts on its own |
| AdGuard Home | Complete the setup wizard; set upstream DNS to `127.0.0.1:5335` (same as reliant) |
| Factorio | No manual step — `services.factorio` generates a default save under `/var/lib/factorio/saves` on first start |
| Automatic Ripping Machine | No manual step — `completed/` (like `raw/`/`transcode/`) is local disk (`custom.autoRip.stateDir`), created by its own `tmpfiles.rules`. `movies/`/`tv/` on the NAS share are created lazily by `custom.mediaSort`'s own first sort |
| tinyMediaManager | Nothing manual, and nothing to scan by hand either — `custom.mediaManager.movieDataSources`/`tvShowDataSources` write its Data Sources declaratively, and `custom.mediaSort` triggers its headless `--updateSources --scrapeUnscraped` run right after every sort (`systemd`'s `OnSuccess=`, see `hosts/excelsior/media.nix`). There is no tmm web UI to check anymore — see Known Gotchas |

After DCS login is saved, set `custom.dcsServer.autoStart = true;` and
rebuild so the DCS server launches with the container.

Starting the container (whether via the control page or manually) does
**not** by itself load a mission — DCS's own log
(`Saved Games/DCS.dcs_serverrelease/Logs/dcs.log`) will show
`Mission list is empty, server not started.` until one is configured in
`serverSettings.lua` or loaded through the WebGUI/webtop. `dcs-control.coppertop.ca`
can upload a `.miz` file into `custom.dcsServer.control.missionsDir` (see
below), but adding it to the active mission list is still a manual step in
the tunneled webtop's WebGUI — uploading and loading are separate.

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

- **`services.factorio.package` strips the Space Age/Quality/Elevated Rails
  data directories from `factorio-headless` via `overrideAttrs`.** Confirmed
  live: setting those three mods `enabled: false` in the runtime
  `mods/mod-list.json` does not stick — the headless server re-enables them
  on every start regardless (a known upstream bug,
  [forums.factorio.com/viewtopic.php?t=117096](https://forums.factorio.com/viewtopic.php?t=117096)).
  nixpkgs' `services.factorio` module has no dedicated option for this either
  — `mods`/`mods-dat` don't intercept built-in expansion content. Deleting the
  three data directories from the package output is the same technique the
  `factoriotools/factorio` Docker image's `DLC_SPACE_AGE=false` variable uses
  internally. Needed here because the host doesn't own Space Age but wants
  players who don't either to be able to join. The override appends to
  `installPhase`, not `postInstall` — confirmed live that a `postInstall`
  override has no effect here, because upstream's `installPhase` is a raw
  script (`mkdir`/`cp`/`patchelf`) that never calls `runHook postInstall`.
- **`services.factorio.extraSettingsFile` points at the
  `factorio/game-password` agenix secret decrypted mode 0444 (world-readable),
  not chowned to a service user.** `services.factorio` runs with
  `DynamicUser = true`, so there's no static UID for agenix to `chown` the
  decrypted file to at activation time — see `docs/secrets.md` for the
  secret's declaration and JSON shape.
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

- **`custom.autoRip` bind-mounts `/home/arm` itself, not just its
  subdirectories.** The image bakes `/home/arm` in at uid:gid 1000:1000;
  ARM's entrypoint UID/GID remap fixes subdirectories under it but not that
  top-level directory's group, so the container refuses to start otherwise
  (confirmed live: `does not have permissions to /home/arm using
  5000:5000... Folder permissions--> 5000:1000`). Host-mounting `/home/arm`
  itself, pre-created and chowned via `systemd.tmpfiles.rules`, sidesteps
  it — see the [ARM Docker Troubleshooting
  wiki](https://github.com/automatic-ripping-machine/automatic-ripping-machine/wiki/Docker-Troubleshooting).
- **`systemd.tmpfiles.rules`' `C`/`C+` does not force-overwrite a
  pre-existing regular file, only a pre-existing directory.** `arm.yaml`
  needed `system.activationScripts` instead.
- **ARM mounts the disc itself, which needs `CAP_SYS_ADMIN`** — dropped by
  default without `--privileged`. `custom.autoRip.extraOptions` adds it
  back.
- **ARM has no metadata provider key by default**, so it can't identify
  discs — they land in `completed/unidentified/`. `custom.autoRip.tmdbApiKeyFile`
  fixes this.
- **ARM's default `HB_ARGS` only kept forced subtitles, not English ones.**
  Pinned via `custom.autoRip.settings.HB_ARGS_DVD`/`HB_ARGS_BD`. The default
  `HB_PRESET_DVD`/`HB_PRESET_BD` are also overridden, to H.265/HEVC presets
  for smaller output at comparable quality.
- **ARM nests its own output one level deeper than `COMPLETED_PATH` itself** — confirmed live: `completed/movies/<title>`, `completed/unidentified/<title>`, not `completed/<title>` directly. `custom.mediaSort` searches for the basename of ARM's `job.path` under `completed/` (up to two levels deep) rather than assuming a fixed relative location, since `job.video_type` from the database is the authoritative movie/series answer regardless of which of ARM's own bucket names it landed under. An unidentified disc (`video_type` outside `movie`/`series`) is left alone in `completed/` for manual sorting.
- **ARM's `DELRAWFILES` only deletes raw/transcode scratch after a *successful* job** — confirmed against ARM's own source. A failed or aborted rip leaves it behind forever with no cleanup of its own. `custom.autoRip.scratchMaxAgeDays` (default 3 days) is the safety net.
- **`custom.autoRip.hardwareEncode` is enabled but untested end-to-end.** Neither ARM's Docker image nor nixpkgs' `handbrake` ships QSV or VAAPI support — `pkgs/handbrake-qsv.nix` builds HandBrake from source with `--enable-qsv` instead. Watch the next real rip (`intel_gpu_top` should show render engine activity) before trusting it; QSV's HEVC encoder is also less compression-efficient than software x265, so output will run larger than the `HB_PRESET_*` names alone suggest.
- **`pkgs.intel-media-sdk` is nixpkgs-marked insecure** (EOL, 5 known local privilege-escalation CVEs) — confirmed live via CI refusing to evaluate otherwise. `vpl-gpu-rt`, the non-insecure successor, only supports Xe/Alderlake+ GPUs, not this host's Skylake HD 530, so there is no non-insecure nixpkgs path to QSV on this hardware. Permitted knowingly in `modules/auto-rip.nix`'s `hardwareEncode` block.
- **`pkgs/handbrake-qsv.nix` forces `-Wno-error=format-security`** — building from source (required for `--enable-qsv`) hits a real upstream bug nixpkgs' own cached binary never does: `libhb/compat.c` passes a non-literal format string to `snprintf`, which `--harden`'s `-Werror=format-security` turns into a build failure. Confirmed live via CI, unrelated to QSV/libva/libvpl themselves.
- **tinyMediaManager has no web UI anymore, by design.** `custom.mediaManager` overrides the image's own CMD to run its CLI (`--updateSources --scrapeUnscraped`) instead of its GUI, and the container only ever starts via `custom.mediaSort`'s `OnSuccess=` — confirmed live that the GUI and a `podman exec`'d CLI run would otherwise fight over tmm's own single-instance lock on its config folder. A wrong scrape match now needs a one-off interactive run (temporarily set `cmd` back, or run the image manually) rather than the always-on `library.coppertop.ca`, which no longer exists (see reliant's own README/config for that removal).
- **`import-disc` requires `--type movie|tv`, and `tv` also requires `--show`/`--season`** — it has no metadata source of its own (no TMDB lookup like ARM, no job database), so it can't infer movie vs. TV or season/episode structure; the operator supplies it at import time. Output lands under `custom.mediaRipping.importDir` (`movies/<title>/` or `tv/<show>/Season N/`), which `custom.mediaSort`'s `importDir` leg merges straight into the library on its next run — no per-item classification needed, since the bucket the operator chose already is the classification.
- **The `sg` kernel module (needed for MakeMKV/Blu-ray) isn't loaded by
  default, only `bsg`.** `hardware.nix` loads it. `/dev/sg1` is this drive,
  `/dev/sg0` an unrelated SATA device — re-check via `readlink -f
  /sys/class/scsi_generic/sg*/device` vs `.../block/sr0/device` if it ever
  changes.

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
  internet-facing; router port-forward for 34197/udp for Factorio if
  internet-facing. Neither port-forward is managed by this repo — once
  either is in place, `custom.ddns` (reliant) already makes
  `dcs.coppertop.ca`/`factorio.coppertop.ca` resolve to the current public
  IP with no further DNS changes, since it tracks the whole
  `*.coppertop.ca` wildcard, not a fixed list of names.
