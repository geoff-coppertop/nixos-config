# Smart Home

The appliance and device layer: Home Assistant, the radio networks that feed it
(Zigbee, Z-Wave, Matter), MQTT, and the standalone ADS-B receiver. The
reverse-proxy/DNS backbone these services register into is
[docs/homelab-network.md](homelab-network.md), not this doc — but `modules/home-assistant.nix`,
`modules/zigbee.nix`, and `modules/adsb.nix` each call `mkTraefikRoute`
themselves to register their own route, the same way `modules/dns.nix` does for
AdGuard. A new smart-home service follows the same pattern; see
[docs/homelab-network.md § Traefik Route Registration](homelab-network.md#traefik-route-registration)
for the mechanics.

The full option-to-module table is
[docs/architecture.md § Custom Options § Homelab services](architecture.md#homelab-services).

## Migration: defiant → reliant

This layer has migrated from `defiant` (Raspberry Pi 4, being retired) to
`reliant` (Gigabyte Brix mini PC) — see
[docs/provisioning.md § Two Phases](provisioning.md#two-phases). Confirmed
live:

- The Zigbee (`/dev/ttyUSB0`, vendor `0658`) and Z-Wave (`/dev/ttyACM0`,
  vendor `10c4`) USB dongles are physically moved to `reliant`, and paired
  devices respond without a re-pair — the shared network key/`securityKeys`
  reuse (below) worked as intended.
- `hosts/reliant/home-assistant/` (a byte-for-byte copy of
  `hosts/defiant/home-assistant/`, comments updated to reference `reliant`)
  is running against `defiant`'s actual restored state (via `restic restore`
  of the `hass` backup job's latest snapshot, not a fresh instance), so the
  entity IDs these automations reference carried over correctly — confirmed
  controlling real devices. Areas/floors (`.storage/core.area_registry`,
  `.storage/core.floor_registry`) aren't excluded from that backup job either,
  so they carried over too; only recorder history/statistics and the Lovelace
  dashboard layout did not (excluded from the `hass` backup job by design).
- The Zigbee network key (`custom.zigbee.networkKeyFile`), the Z-Wave
  `securityKeys` (`custom.zwave.secretsConfigFile`), and the ADS-B receiver
  location (`custom.adsb.locationEnvFile`) are all **reused** from
  `defiant`'s existing secrets, not regenerated — `reliant` is a rekeyed
  recipient of the *same* `.age` files, not new secret content. This is what
  let the radios keep working without a re-pair: the physical
  coordinator/controller's own NVRAM/NVM already held each network's key, and
  a mismatched key here would have made `zigbee2mqtt` treat it as a new,
  wrong network, or forced a Z-Wave re-pair.
- The three appliance backup jobs' `restic-password` secrets (`hass`,
  `zigbee2mqtt`, `zwave-js`) also **reuse** `defiant`'s existing job-keyed
  secrets and are confirmed running clean.
- `custom.zwave.port = 3001` carries over to `reliant` too — 3000 collides
  with AdGuard Home's admin UI, also enabled on `reliant`.
- **`custom.backups.users.zwave-js.paths` is `/var/cache/zwave-js`, not
  `/var/lib/zwave-js`** — confirmed live that the latter never gets created
  on either host (`modules/zwave.nix` only seeds it via a tmpfiles rule that
  fires solely when `secretsConfigFile` is still the module's own default
  placeholder; both hosts override it to an agenix path, so that rule never
  runs). The real network cache (device values/metadata, keyed by home ID)
  lives at `/var/cache/zwave-js` via systemd's `CacheDirectory=`, itself a
  symlink to `private/zwave-js` — same shape as `defiant`'s existing
  `/var/lib/AdGuardHome` symlink gotcha. `defiant`'s own `zwave-js` backup
  job has the identical bug and has likely been backing up nothing this
  whole time; not yet fixed there.
- The LAN's DHCP-advertised DNS server has been repointed at `reliant`
  directly (see
  [docs/homelab-network.md § Migration: defiant → reliant](homelab-network.md#migration-defiant--reliant)),
  so `reliant` is the live DNS/appliance primary. `defiant` keeps running
  every one of these services untouched in parallel; removing them from
  `hosts/defiant/` and retiring the Pi is a separate, later step.
- Matter server currently doesn't start on `reliant` (or `defiant`) — a
  shared `modules/matter.nix` bug (upstream `python-matter-server` hangs
  fetching PAA certs from the DCL), tracked and fixed in PR #112, not
  specific to this migration.

## Home Assistant

The **service** — package, `extraComponents`, HTTP and proxy setup — is
configured by `modules/home-assistant.nix` plus the host's `extraComponents` in
`configuration.nix`. The module sets `configWritable = true`, so UI-created
automations are written to `automations.yaml` alongside the Nix-declared ones.

`sun = {}` is set explicitly in the module: unlike `ssdp` and `zeroconf`, which
are part of HA's always-on core bootstrap, `sun` is never set up unless
referenced, and `sun.sun` does not exist at all without it. It needs no extra
packages, so it is not an `extraComponents` entry.

### Declarative automations

Automations are declared in Nix, **one file per concern**, under
`hosts/<host>/home-assistant/`. A `default.nix` in that directory imports each
concern file, and the host's `configuration.nix` imports the directory
(`./home-assistant`, which resolves to its `default.nix`).

```text
hosts/defiant/home-assistant/
├── default.nix           # imports each concern file below
├── outside-lights.nix    # arrival/departure outside lights
├── door-locks.nix        # nightly door lock
└── presence-lighting.nix # presence-driven office lighting
```

Rules for this layer:

- **One feature-area per file**, named for the concern — not a single catch-all
  automations file, and not a flat `hosts/<host>/home-assistant.nix` (that name
  would collide with the `modules/home-assistant.nix` service module). To add an
  automation, create `hosts/<host>/home-assistant/<concern>.nix` and import it in
  that directory's `default.nix`.
- Each file contributes to `services.home-assistant.config."automation manual"`,
  a list. NixOS merges the lists across files, so the concern files coexist
  without conflict. Use the `"automation manual"` key, **not** bare
  `"automation"`, so Nix-declared automations coexist with UI-created ones.
- A concern file may also hold that concern's related HA config — helpers,
  scripts, template sensors — not just automations.
- This directory holds **only** per-concern automation and config content. The
  service itself belongs in the module and the host configuration.

### Automation file skeleton

Every existing concern file follows this shape. Copy it rather than improvising —
the key order, `mode`, and the `target.entity_id` form are consistent across all
of them.

```nix
# Home Assistant automation for <host>: <one-line summary>.
#
# <What it does, and when. Be explicit about triggers that fire regardless of
# current state.>
#
# <Which physical devices back these entities and how they reach HA — the
# integration, the bridge, and which custom.* option or extraComponents entry in
# hosts/<host>/configuration.nix makes that work.>
#
# <The literal entity IDs this file uses.>
#
# Declared under the "automation manual" key (not bare "automation") so these
# coexist with any UI-created automations, matching
# services.home-assistant.configWritable = true. NixOS merges this list with the
# "automation manual" lists in the sibling files under this directory (see
# default.nix).
{
  services.home-assistant.config."automation manual" = [
    {
      id = "snake_case_unique_id";
      alias = "Human sentence shown in the HA UI";
      description = "Full sentence explaining the intent.";
      mode = "single";
      trigger = [
        {
          platform = "time";
          at = "21:00:00";
        }
      ];
      action = [
        {
          service = "lock.lock";
          target.entity_id = [
            "lock.front_door"
          ];
        }
      ];
    }
  ];
}
```

Conventions the skeleton encodes:

- Keys in the order `id`, `alias`, `description`, `mode`, `trigger`,
  `condition` (only when needed), `action`.
- `mode = "single";` on every automation.
- `id` snake_case and unique across all files, since NixOS merges them into one
  list; `alias` a human sentence; `description` a full sentence of intent.
- Actions always use `target.entity_id = [ … ]`, never a top-level `entity_id`.
- Entity IDs always fully qualified and domain-prefixed
  (`switch.front_entry_lights`, not `front_entry_lights`).
- Trigger platforms in use here: `time` (with `at`), `sun` (with `event`),
  `state` (with `entity_id`/`to`, optionally `for`), and `homeassistant` (with
  `event = "start"`).

Where several rooms or devices share one pattern, write a `mk*` function and
`map` it over a list rather than repeating the block — `presence-lighting.nix`
does this for per-room presence lighting.

**Verify entity IDs before writing them.** They are assigned by Home Assistant
at pairing or commissioning time and are not predictable from the device name —
a wrong ID produces an automation that loads cleanly and silently never fires.
Check against the running instance (Developer Tools → States, or the entity
list) rather than guessing.

### Choosing `extraComponents`

HA's `default_config` baseline in nixpkgs is small, and a missing dependency
surfaces as an "Invalid config" notification rather than a clear error. Worse,
`default_config`'s setup can abort partway through on one component's crash,
taking unrelated components down with it — a `conversation` failure
(`ModuleNotFoundError: No module named 'hassil'`) previously took out `met`,
which had been working fine on its own.

When an integration misbehaves, check `journalctl` and nixpkgs'
`component-packages.nix` for what the component actually needs, then add it to
`extraComponents` rather than assuming `default_config` covers it. Note that some
integrations are distinct platforms needing their own entry — `google_translate`
is separate from the core `tts` component, for instance.

## Radio Networks

### Zigbee

`custom.zigbee` runs Zigbee2MQTT against a USB coordinator on
`serialPort` (default `/dev/ttyUSB0`), with the network key read from
`networkKeyFile`. It publishes to the MQTT broker; Home Assistant discovers
entities from `zigbee2mqtt/bridge/...` topics, which is why the `mqtt` component
must be in `extraComponents` — Zigbee2MQTT has no HA component of its own.

### Z-Wave

`custom.zwave` runs the Z-Wave JS WebSocket server against `serialPort` (default
`/dev/ttyACM0`), reading `securityKeys` from `secretsConfigFile`. Home Assistant
connects to it with the `zwave_js` component, which does not ship in the
`default_config` baseline.

`zwave-js-server` does **not** generate `securityKeys` itself. Leaving the
default placeholder crash-loops the service indefinitely. Generate real keys
before first deploy — see
[docs/secrets.md § Shared hardware and domain secrets](secrets.md#shared-hardware-and-domain-secrets).

The module's default port is 3000, which collides with AdGuard Home's admin UI on
any host running both. Set `port = 3001` (or anything free) in that case.

### Both

Neither radio's key can be rotated cheaply: regenerating the Zigbee network key
or the Z-Wave security keys after devices are paired or included breaks every one
of them and forces a full re-pair. Create both before the first boot and store
them in Bitwarden.

Serial device paths are not stable guesses. Confirm them on the host after first
boot with `ls /dev/tty{ACM,USB}*` before pinning them in the config.

## Matter And ADS-B

`custom.matter` runs python-matter-server (`ws://localhost:5580/ws`), backing
Matter-bridged devices such as the Aqara U100 locks. `custom.adsb` runs a
standalone dump1090 receiver with its own map UI — it does not feed Home
Assistant and has no automation surface of its own.
