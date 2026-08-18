# defiant

Headless aarch64 homelab server (Raspberry Pi 4). Runs DNS, Traefik, Home
Assistant, Matter, Zigbee2MQTT, Z-Wave JS, and ADS-B.

The reusable service layer these options configure is documented in
[docs/homelab-network.md](../../docs/homelab-network.md). Provisioning steps are in
[docs/provisioning.md § SD-Card Hosts](../../docs/provisioning.md#sd-card-hosts-defiant).

## Machine Files

| File | Purpose |
| --- | --- |
| `configuration.nix` | Boot, hardware, networking, and every `custom.*` service setting |
| `default.nix` | home-manager attachment |
| `secrets.nix` | `age.secrets` declarations for this host |
| `home/thomasga.nix` | Per-machine home-manager profile (headless) |
| `home-assistant/` | Declarative HA automations, one file per concern |
| `provision-type` | `sd-card` |

## Hardware And Access

- aarch64 Raspberry Pi 4, booted from SD card via
  `installer/sd-card/sd-image-aarch64.nix` and extlinux (GRUB disabled).
- Reserved LAN IP `192.168.20.10`, set as a DHCP reservation in Unifi and
  mirrored into `lanIp` in `configuration.nix`.
- Zigbee coordinator on `/dev/ttyUSB0`, Z-Wave controller on `/dev/ttyACM0`.
  Both are passed through by a `udev.extraRules` entry matching vendor IDs `0658`
  and `10c4` into the `dialout` group; `thomasga` is in that group here.
- Headless. `profiles/desktop` is deliberately **not** imported — there is no
  display server.
- SSH key only: `PasswordAuthentication`, `KbdInteractiveAuthentication`, and
  `PermitRootLogin` are all off.
- `security.sudo.wheelNeedsPassword = false`. The authorized-key check is the
  actual gate, since there is no physical console; a sudo password on top of it
  would only block unattended remote deploys (`nixos-rebuild --target-host`)
  without adding real security.

## Services And URLs

| Service | URL | Port behind Traefik |
| --- | --- | --- |
| AdGuard Home (this host) | `https://dns1.coppertop.ca` (behind Authelia) | 3000 |
| AdGuard Home (excelsior, proxied cross-host — see its `dns2` router below) | `https://dns2.coppertop.ca` (behind Authelia) | excelsior `192.168.1.10:3000` |
| Home Assistant | `https://home.coppertop.ca` (behind Authelia, in front of HA's own auth) | 8123 |
| Zigbee2MQTT | `https://zigbee.coppertop.ca` (behind Authelia) | 8082 |
| ADS-B map | `https://adsb.coppertop.ca` | 8080 |
| Authelia (SSO portal) | `https://auth.coppertop.ca` | 9091 |
| lldap (directory admin UI) | `https://ad.coppertop.ca` (own login, not behind Authelia — see Known Gotchas) | 17170 |
| Z-Wave JS | `ws://localhost:3001` (not proxied) | 3001 |
| Matter server | `ws://localhost:5580/ws` (not proxied) | 5580 |
| MQTT broker | `localhost:1883` (not proxied) | 1883 |
| lldap (LDAP protocol) | `defiant.local:3890` (not proxied — LDAP isn't HTTP) | 3890 |

`dns1`/`dns2` naming: excelsior runs a second, fully independent unbound +
AdGuard instance for real DNS redundancy (see
[hosts/excelsior/README.md](../excelsior/README.md)) — Traefik only runs
here on defiant, so its admin UI is proxied cross-host via a manually
defined router in `configuration.nix` (`modules/dns.nix`'s self-registration
only ever points at `127.0.0.1`).

## First-Time Service Setup

| Service | Action |
| --- | --- |
| AdGuard Home | Complete the setup wizard; set upstream DNS to `127.0.0.1:5335` |
| lldap | Log into `https://ad.coppertop.ca` with the initial admin password (agenix `lldap/initial-admin-password`); household accounts declared in `custom.lldap.users` (see `hosts/defiant/lldap-accounts.nix`) get reconciled in automatically, each sets their own password on first login |
| Authelia | First login at `https://auth.coppertop.ca` (or any protected subdomain) prompts for TOTP/WebAuthn enrollment — do this once per household member before relying on a protected route |
| Home Assistant | Restore a backup, or complete onboarding |
| Zigbee2MQTT | Enable join mode and pair devices (see the notes below) |
| Z-Wave JS | In HA → Integrations, connect to `ws://localhost:3001`, then include devices |
| Matter | In HA → Integrations, add Matter and commission the hub's pairing code |
| HomeKit accessories | In HA → Integrations, pair each accessory's 8-digit code |
| Bambu Lab | In HA → Integrations, choose LAN mode (disables the Handy app) or cloud mode |

## Device Pairing Notes

- **IKEA Somrig button** — pair normally; automations should use `initial_press`
  only, as `long_press` and `double_press` are unreliable. Re-pair after any OTA
  update.
- **IKEA VALLHORN / PARASOLL** — if the interview fails, retry pairing. Do not
  set occupancy timeout below 90 s on any IKEA motion sensor.
- **IKEA E1745 motion sensor** — do **not** apply OTA firmware; it disables
  motion detection.
- **IKEA STARKVIND air purifier** — no known issues; pair normally.

## DNS Bypass

Clients needing unfiltered DNS — this skips AdGuard's ad-blocking but keeps
`coppertop.ca` resolution:

```bash
dig @defiant.local -p 5335 home.coppertop.ca
```

Point a device at `192.168.20.10:5335` in its DNS settings to bypass AdGuard
permanently.

## Known Gotchas

These were all confirmed on the running machine and are the reason the config
looks the way it does. Changing them back reintroduces a real failure.

- **`custom.dns.lanSubnet` is overridden to `192.168.0.0/16`.** The module
  default (`192.168.1.0/24`) and a narrower per-host override
  (`192.168.20.0/24`, this host's own VLAN) each only cover one of the
  network's 3 VLANs. Widened on both defiant and excelsior so unbound's
  `access-control` allows direct bypass queries on port 5335 from any of
  them.
- **`custom.dns.adminSubdomain = "dns1"`.** Renamed from the module default
  `"dns"` now that excelsior runs a second, independent DNS instance —
  `dns1`/`dns2` naming pairs the two admin UIs.
- **`custom.zwave.port = 3001`.** The module default of 3000 is already
  AdGuard Home's admin UI on this host — confirmed with `ss -tlnp` and
  `lsof -i :3000` showing AdGuardHome, not zwave-js, holding the port, which is
  why zwave-js crash-looped on `EADDRINUSE`.
- **`zwave-js` requires generated `securityKeys`.** The module default left an
  empty placeholder, crash-looping the service through 439 restarts. There are no
  keys to "extract" from the controller — generate real random ones.
- **`mqtt` must be in `extraComponents`.** Zigbee2MQTT has no HA component of its
  own; without `mqtt`, its `zigbee2mqtt/bridge/...` discovery messages publish
  unheard and no entities are created.
- **`zwave_js` must be in `extraComponents`.** It is not in the `default_config`
  baseline; adding it through the UI fails with "Invalid handler specified".
- **The AdGuard backup path is capitalized.** `/var/lib/AdGuardHome` is a symlink
  to `private/AdGuardHome`; the lowercase path does not exist on this
  case-sensitive filesystem, so a lowercase entry silently backs up nothing.
- **`custom.lldap` runs as a static `lldap` user, overriding the module's own
  `DynamicUser` default.** lldap's `settings.*_file` options (JWT secret,
  admin password) are read directly by the lldap process itself after it
  drops privileges, not loaded by systemd-as-root the way Authelia's
  `LoadCredential`-backed secrets are — a `DynamicUser`'s UID is only
  allocated at service start, so an agenix secret can't be chowned to it
  ahead of time. `systemd.services.lldap.serviceConfig.DynamicUser =
  lib.mkForce false;` plus a real `users.users.lldap` makes the secret
  ownership deterministic, matching the rest of this repo's agenix
  `owner = "<service>"` convention.
- **lldap's admin UI (`ad.coppertop.ca`) and Authelia's own portal
  (`auth.coppertop.ca`) are deliberately not behind the `authelia` Traefik
  middleware.** Authelia protecting its own login page is an obvious
  lockout; Authelia protecting lldap's UI is the same failure one hop
  removed, since Authelia authenticates *against* lldap — if lldap is ever
  down, misconfigured, or mid-bootstrap before any accounts exist, there
  would be no way through Authelia to reach the tool that fixes it. Each
  relies on its own login (lldap's built-in one; Authelia's password+2FA)
  plus network scoping instead.
- **lldap's bootstrap reconciliation (`lldap-bootstrap.service`) is
  triggered by an activation script on every `nixos-rebuild switch`, not
  a content-hash `restartTrigger`.** `DO_CLEANUP=true`'s purpose is
  pruning accounts/group-memberships created out-of-band through lldap's
  own web UI, which a trigger based only on the generated JSON's content
  would miss between rebuilds where the JSON itself doesn't change.
  lldap/lldap#745 reports repeated `bootstrap.sh` runs via the GraphQL API
  can duplicate group memberships on some versions — not reproduced yet
  against the pinned lldap version; verify group membership after the
  first several real reruns before trusting `DO_CLEANUP` fully in the
  steady state, since upstream's own docs don't flag it as a known issue.
- **`ssdp` needs an explicit entry.** It is one of `default_config`'s
  always-loaded discovery integrations, but its dependencies are not part of the
  small nixpkgs `default_config` baseline.
- **The SD card is fixed-size, unlike the systemd-boot hosts' NVMe/SSD.**
  `boot.loader.generic-extlinux-compatible.configurationLimit` had no override
  (module default 20) while old boot generations accumulated unbounded,
  causing a `nix-copy-closure` deploy to fail with "No space left on device".
  Capped at 10 first (matching `enterprise-d`/`excelsior`'s `systemd-boot`
  `configurationLimit`), but a full `nix-collect-garbage -d` at that cap —
  which also drops all old generations, not just excess ones — still only got
  the 30G card down to a ~23-24G floor. Both `configurationLimit` and this
  host's `custom.nix.gc.keepGenerations` override (a per-host override of
  `profiles/common/base.nix`'s `custom.nix.gc.keepGenerations` option, shared
  default 10) are now dropped to 3, and `nix.settings.min-free`/`max-free`
  (2GiB/5GiB, scoped to this host only) trigger GC proactively mid-build or
  mid-deploy instead of failing outright. Check `df -h /` before a large
  deploy regardless — see
  [docs/provisioning.md § SD-Card Hosts](../../docs/provisioning.md#sd-card-hosts-defiant).

## Backup Jobs

Six entries under `custom.backups.users`, each with its own restic repository
and its own `restic-password` secret:

| Entry | Paths |
| --- | --- |
| `hass` | `/var/lib/hass`, excluding `.storage/lovelace*` and `home-assistant_v2.db` |
| `zigbee2mqtt` | `/var/lib/zigbee2mqtt` |
| `zwave-js` | `/var/lib/zwave-js` |
| `adguardhome` | `/var/lib/AdGuardHome` |
| `lldap` | `/var/lib/lldap` (StateDirectory name from `services.lldap`) |
| `authelia` | `/var/lib/authelia-main` (StateDirectory name for the `main` Authelia instance) |

The `zigbee2mqtt`, `zwave-js`, `lldap`, and `authelia` paths are the standard
NixOS module state directories and have **not** been verified against the
running machine yet — confirm them with `ls` on the host, the same way the
AdGuard path and the serial ports were.

See [docs/backups.md](../../docs/backups.md).
