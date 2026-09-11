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

## Home Assistant

The **service** — package, `extraComponents`, HTTP and proxy setup — is
configured by `modules/home-assistant.nix` plus the host's `extraComponents` in
`configuration.nix`. The module sets `configWritable = true`, so UI-created
automations are written to `automations.yaml` alongside the Nix-declared ones.

`sun = {}` is set explicitly in the module: unlike `ssdp` and `zeroconf`, which
are part of HA's always-on core bootstrap, `sun` is never set up unless
referenced, and `sun.sun` does not exist at all without it. It needs no extra
packages, so it is not an `extraComponents` entry.

`mobile_app = {}` is set explicitly in the module for the same reason as
`sun`: `extraComponents` only bundles the `mobile_app` Python package into the
closure, it does not make HA load it at boot, and `mobile_app` has no "Add
Integration" UI flow to trigger setup afterward — it's driven entirely by the
companion app's own registration API call, which is the very call that fails
with "The mobile_app component is not loaded" if this entry is missing. A
host still needs `"mobile_app"` in its own `extraComponents` too (that
installs the package); the YAML entry here is what makes HA actually load it.

### HTTP config: no longer declarative

`modules/home-assistant.nix` used to also set `config.http.trusted_proxies`
and `config.http.use_x_forwarded_for` — needed because Traefik fronts HA on
every host with `custom.traefik.enable` (self-registered by this module), so
HA has to trust Traefik's `X-Forwarded-For` header to see real client IPs
rather than always `127.0.0.1`. Confirmed live: newer HA versions deprecate
YAML `http:` config entirely in favor of Settings > System > Network,
auto-importing whatever YAML value existed once into HA's own
`.storage` and repair-warning to remove the YAML block on every boot
afterward until it's gone (stops being read at all from HA `2027.2.0`).

Removed from the module rather than left in: `configWritable = true` means
the once-imported value already persists in an existing instance's own
`/var/lib/hass/.storage`, independent of this file, so removing the YAML is
safe for any host that has already run with it set (`reliant`, confirmed).
For a **fresh** install with no existing `.storage` (a from-scratch install on
any future host), there is no longer a declarative way to set
this — a one-time manual step after first boot is required: Settings >
System > Network > enable "Use X-Forwarded-For" and add `127.0.0.1` as a
trusted proxy.

### Firewall: `openFirewall` removed upstream

`modules/home-assistant.nix` no longer sets
`services.home-assistant.openFirewall`. nixpkgs used to derive the frontend
port by parsing it out of the module's own rendered YAML config at eval
time; now that HTTP config isn't declarative any more (previous section),
that's no longer possible, and the option was removed via
`mkRemovedOptionModule` — defining it at all, `true` or `false`, is now an
eval-time assertion failure ("no longer has any effect; please remove it").

Deleting the line is a pure no-op here: it was already `false`, and `false`
never added a firewall rule in the first place. The intended posture — HA's
frontend port (8123) closed to everything except a narrow LAN carve-out for
Sonos UPnP callbacks, with all other access going through Traefik — is
unchanged and is carried entirely by `hosts/reliant/configuration.nix`'s
`networking.firewall.extraCommands` iptables rule and the Traefik route
registration in this module, both of which already hardcode `8123`. Since
nixpkgs can no longer discover the port at eval time, that hardcoding is now
load-bearing rather than incidental: if HA's frontend port is ever changed
from 8123, it has to be updated by hand in both of those places (see
`hosts/reliant/README.md` § Known Gotchas for the exact locations).

### Core location: latitude/longitude/elevation, unlike `http:`

`custom.home-assistant.locationEnvFile` (set on `reliant`, same value as
`custom.adsb.locationEnvFile`) points at the shared
`secrets/location/coordinates.age` — see
[docs/secrets.md § Secret Inventory](secrets.md#secret-inventory). When set,
the module both adds it as the `home-assistant` systemd unit's
`EnvironmentFile` and sets `config.homeassistant.{latitude,longitude,elevation}`
to `"!env_var LOCATION_LAT"` / `"!env_var LOCATION_LON"` /
`"!env_var LOCATION_ELEVATION"`.

`!env_var NAME` is a real Home Assistant YAML tag (`annotatedyaml`'s loader,
the same loader used for `configuration.yaml`) that reads an environment
variable at config-load time and raises if it's unset — confirmed against
that library's source, not guessed. Getting a literal `!word ...` tag past
`pkgs.formats.yaml`'s generic serializer (which would otherwise quote it as
an inert string) works because `modules/services/home-automation/
home-assistant.nix`'s `renderYAMLFile` sed-unquotes any generated string
matching `'!word rest'` — this is the module's own documented mechanism for
`!secret`, confirmed against its source; `!env_var` matches the same pattern.

Unlike [`http:` above](#http-config-no-longer-declarative), this is **not**
deprecated or onboarding-only: confirmed against HA's own `core_config.py`,
`homeassistant:` YAML keys (latitude, longitude, elevation, and others) are
applied from YAML on *every* startup, not written back to `.storage` and
then ignored — so this stays in sync with the secret on every rebuild,
rather than only seeding it once. `zone.home` (and anything derived from
it — `met`'s weather forecast, `sun.sun`'s solar calculations) reflects
this repo's own coordinates as a result.

The secret currently only carries `LOCATION_LAT`/`LOCATION_LON`
(`modules/adsb.nix`'s original fields) plus `LOCATION_ELEVATION`, added for
this. A wrong or missing elevation is a known cause of a several-degree
`met` forecast-vs-actual offset — met.no's forecast API adjusts temperature
for the delta between its grid cell's elevation and whatever elevation the
requesting instance reports, so an elevation left at HA's default (0m,
seeded during onboarding before this wiring existed) reads as a
sea-level-adjusted forecast at any real elevation.

### Declarative automations

Automations are declared in Nix, **one file per concern**, under
`hosts/<host>/home-assistant/`. A `default.nix` in that directory imports each
concern file, and the host's `configuration.nix` imports the directory
(`./home-assistant`, which resolves to its `default.nix`).

```text
hosts/reliant/home-assistant/
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
- Trigger platforms in use here: `time` (with `at`), `time_pattern` (with
  `minutes`, e.g. `"/10"` for every ten minutes), `sun` (with `event`), `state`
  (with `entity_id`/`to`, optionally `for`), and `homeassistant` (with
  `event = "start"`).

Where several rooms or devices share one pattern, write a `mk*` function and
`map` it over a list rather than repeating the block — `presence-lighting.nix`
does this for per-room presence lighting. `kids-wake-lights.nix` extends the
same pattern with per-room `input_boolean`/`input_datetime` helpers declared
alongside the automations, so a value like a wake time is adjustable live from
Settings > Devices & Services > Helpers without touching Nix or rebuilding —
the automations trigger off the helper entities themselves
(`platform: time, at: input_datetime.<slug>_wake_weekday`) rather than a
Nix-baked literal time.

`door-locks.nix` shows a different reusable shape — **periodic enforcement with
a hold-off**. A `time_pattern` sweep gated by a `time` condition (the overnight
window) runs an action that `repeat`s over the lock entities and, per door,
locks it only when a `template` condition says it has been left unlocked and
untouched past a hold-off (`now() - states[repeat.item].last_changed` against a
Nix-interpolated `holdOffSeconds`). That keeps a periodic "always ends up
locked" guarantee while backing off from the last manual interaction, and it
degrades safely if the lock does not report manual operations — the sweep still
re-locks on its next pass. Prefer this over a one-shot `time` trigger whenever a
state must be *held* rather than set once.

**Verify entity IDs before writing them.** They are assigned by Home Assistant
at pairing or commissioning time and are not predictable from the device name —
a wrong ID produces an automation that loads cleanly and silently never fires.
Check against the running instance (Developer Tools → States, or the entity
list) rather than guessing.

### Declarative dashboards: one file, many views

`services.home-assistant.lovelaceConfig`/`lovelaceConfigFile` can only ever
generate content for a single dashboard file (`ui-lovelace.yaml`) — confirmed
against the nixpkgs `home-assistant` module source
(`nixos/modules/services/home-automation/home-assistant.nix`).
`config.lovelace.dashboards.<name>` entries beyond the one this produces
carry only metadata (title/icon/filename), not card content, so there is no
way to declare a second, independently-titled sidebar dashboard from Nix.

`hosts/reliant/home-assistant/climate-dashboard.nix` is that one file. Each
unrelated concern that wants its own page becomes a new `view` (tab) inside
it — e.g. "Climate" and "Bedtime" — rather than a new file each owning its
own dashboard. The sidebar entry itself is titled generically ("Home"), not
after whichever concern happened to be there first.

### Automated entity ID check

`tools/check_ha_entities.py <host>` automates the check above: it greps
`hosts/<host>/home-assistant/*.nix` for entity_id string literals (both the
`target.entity_id = [ "lock.front_door" ]` list form and the bare
`entity_id = "sun.sun";` trigger/condition form), reads the live entity
registry from the host over SSH
(`ssh <host> sudo cat /var/lib/hass/.storage/core.entity_registry` —
`/var/lib/hass` is `services.home-assistant`'s `StateDirectory`, the same
path already referenced by the `hass` backup job's `excludePatterns` in each
host's `configuration.nix`), and reports any referenced entity_id that isn't
in the live registry. It exits non-zero when anything is missing, so it can
gate a migration or run periodically. Run it:

```bash
python3 tools/check_ha_entities.py reliant
```

Run it before cutting traffic over in a host migration (confirm the restored
`.storage` state actually carried every referenced entity), after any device
re-pair, and periodically thereafter to catch drift — an entity_id can go
stale any time a device is removed, re-paired, or renamed in the UI.

**Known limitation**: this is a grep over string literals, not a Nix
evaluator. `presence-lighting.nix`'s `mkPresenceLighting` takes `presence`
and `lights` as function parameters — the tool still catches these today
because every call site passes them as literal strings, which is what it
scans for. If an entity_id were ever sourced from something other than a
literal at the call site (a value computed from an import, an environment
variable, string concatenation split across lines, etc.), the tool would
silently miss it — it does not evaluate Nix expressions, so it cannot follow
a value back through a variable or function argument to find where it
originated. Treat a clean run as "every entity_id written as a literal
string resolves", not as an exhaustive guarantee.

**`sun.sun` is deliberately skipped, not checked**: `core.entity_registry`
only contains entities backed by a config-entry integration with a
`unique_id`. `sun.sun` is set up via the bare `sun = {}` YAML platform (see
§ Home Assistant above), not a config-entry integration, so it never appears
in the registry even when it's working correctly — confirmed live against
`reliant`, where it was the sole entity_id ever reported "missing" until the
tool special-cased it. `check_ha_entities.py`'s `NON_REGISTRY_DOMAINS` set
lists domains known to work this way and reports them separately
("skipped") instead of flagging them as drift. If a future automation
references another registry-less entity (any other bare-YAML-platform
domain, e.g. a template or group entity without a `unique_id`), add its
domain to `NON_REGISTRY_DOMAINS` rather than treating the tool's report as
ground truth for that entity_id.

### Choosing `extraComponents`

HA's `default_config` baseline in nixpkgs is small, and a missing dependency
surfaces as an "Invalid config" notification rather than a clear error. Worse,
`default_config`'s setup can abort partway through on one component's crash,
taking unrelated components down with it — a `conversation` failure
(`ModuleNotFoundError: No module named 'hassil'`) previously took out `met`,
which had been working fine on its own.

When an integration misbehaves, check `journalctl` and nixpkgs'
`component-packages.nix` for what the component actually needs, then add it to
`extraComponents` rather than assuming `default_config` covers it. `hue`
(backing `hosts/reliant/home-assistant/kids-wake-lights.nix`) was added this
way pre-emptively, from reading `component-packages.nix` rather than a live
failure: it's config-flow/discovery-based like `homekit_controller`/`matter`,
but unlike those it isn't part of `default_config` and pulls in its own
`aiohue` dependency, so selecting "Hue" in the Integrations UI without this
entry would fail importing that dependency the moment the config flow runs,
even though the UI lists "Hue" as an option regardless. Note that some
integrations are distinct platforms needing their own entry — `google_translate`
is separate from the core `tts` component, for instance.

`wiz` (WiZ Connected smart bulbs) is the same config-flow-only shape as `hue`
and `broadlink`: confirmed present in nixpkgs' `component-packages.nix`
(pulling in `pywizlight`/`ifaddr`), so it's core HA and installs via
`extraComponents` alone — no `services.home-assistant.customComponents`
packaging like `wiim` needed. Unlike Hue, it's local-only UDP discovery/control
(no bridge, no cloud account, no secret file). A new bulb is paired via
Settings > Devices & Services > Add Integration > WiZ; entity IDs aren't known
until that pairing happens (see § Declarative automations above on verifying
entity IDs before referencing them). As of this writing there's no
Nix-declared automation using a `light.*` entity from this integration, so
there is no `hosts/reliant/home-assistant/wiz-lights.nix` file — only the
`extraComponents` entry.

Some components additionally need an explicit YAML block in
`modules/home-assistant.nix`'s `services.home-assistant.config`, the same as
`sun`/`mobile_app` there: NixOS's home-assistant module has its own fixed
`defaultIntegrations` list (frontend, automation, the `input_*` helpers, and
similar — confirmed against that module's source) that's always set up
regardless of YAML, but `history`/`recorder`/`logbook`/`sun`/`mobile_app`
aren't on it. Unlike `ssdp` (pulled in automatically as a manifest dependency
of `sonos`/`apple_tv`, so it only needed the `extraComponents` entry), nothing
else in this repo references `history`/`recorder`, so — confirmed live, a
history-graph Lovelace card reported "History integration is disabled" with
only the `extraComponents` entries present — both also need bare
`recorder = {};` / `history = {};` keys to ever be attempted at all.
`history` needs `recorder` configured to have anything to read, so the two
are always added together.

### Wiim: community integration, not core `linkplay`

Core HA's `linkplay` integration fails to complete setup against Wiim Pro
units — confirmed live on `reliant`: its SSDP-discovery validation call,
`getMetaInfo`, gets back the literal string `"Failed"` instead of JSON, which
`json.loads()` can't parse (`Expecting value: line 1 column 1 (char 0)`). That
exception aborts the config flow before it ever creates an integration entry
or a discovered-device card, so nothing shows up in the UI at all — not a
missing-dependency gap `extraComponents` can close, and not specific to this
repo's packaging. Other `httpapi.asp` commands work fine against the same
device (`getStatusEx` returns full, valid JSON), so it's specifically
`getMetaInfo` the firmware doesn't answer correctly. Tracked upstream at
[home-assistant/core#145132](https://github.com/home-assistant/core/issues/145132)
and related open issues (#123088, #132922, #125770, #125328); no fix has
landed in `home-assistant/core` as of the nixpkgs revision this flake
currently pins.

The community-maintained `wiim` integration
([github.com/mjcumming/wiim](https://github.com/mjcumming/wiim)) already
handles this device's `getMetaInfo` response correctly. It's a third-party
`custom_components` (HACS) package, not part of Home Assistant core, so
nixpkgs' `component-packages.nix` has no entry for it and `extraComponents`
can't install it. `pkgs/home-assistant-wiim.nix` packages it declaratively via
`buildHomeAssistantComponent` instead, wired in through
`services.home-assistant.customComponents` (`hosts/reliant/configuration.nix`)
rather than `extraComponents` — see that module's `README.md § Known Gotchas`
entry. Its own dependency, the `pywiim` client library (also not in nixpkgs),
is packaged separately in `pkgs/pywiim.nix`, built against
`home-assistant.python.pkgs` specifically (not the general `python3Packages`)
so its transitive dependencies share Home Assistant's own Python environment
rather than risking a second, conflicting copy.

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

### Matter: pinned PAA root certs, not live DCL fetch

Upstream python-matter-server fetches current PAA (Product Attestation
Authority) root certificates from the Distributed Compliance Ledger (DCL) and
the `project-chip/connectedhomeip` Git repo on every `server.start()`, before
it binds its websocket port. As of this writing, DCL serves at least one
certificate that fails strict ASN.1 parsing in the `cryptography` library;
that raises an uncaught `ValueError` inside
`matter_server/server/helpers/paa_certificates.py` (only `ClientError`/
`TimeoutError` are caught around the fetch call in `server.py`), so
`start()` never completes. systemd still reports the unit `active (running)`
— the process doesn't crash, aiorun just logs "Task exception was never
retrieved" and idles — so this fails silently unless you check the journal
for the traceback. Tracked upstream at
[nixpkgs#377136](https://github.com/NixOS/nixpkgs/issues/377136); as of the
nixpkgs revision this flake currently pins, no workaround has landed there.

`modules/matter.nix` works around this by overriding
`services.matter-server.package`: it patches `fetch_certificates()` itself in
`matter_server/server/helpers/paa_certificates.py` to install a static,
pinned set of production PAA root certs instead of fetching anything over
the network. Patching the function directly (rather than its call site
inside `server.py`'s `start()`, the original approach) means it's a real,
top-level, importable function — so a standalone test,
`tests/server/test_paa_certificates_pinned.py`, is added by the same
`postPatch` and calls the patched function directly to assert it actually
installs the pinned certs. That test exists because the *only* upstream
test that exercises `fetch_certificates()` at all is `test_server_start`,
which has to stay deselected (see `disabledTests` in `modules/matter.nix`)
for an unrelated reason: it fails in this build sandbox on a zeroconf
IPv6-multicast socket call, not on anything this patch touches. The pinned
certs come from `project-chip/connectedhomeip`'s
`credentials/production/paa-root-certs` directory — the same source
`fetch_git_certificates()` would otherwise pull from at runtime — fetched at
build time via `pkgs.fetchgit` with `rootDir` set to that path (a sparse
checkout, not the full multi-gigabyte SDK tree) and pinned to a commit via
`pinnedPaaCertsRev`.

**Checking whether this is fixed upstream**: nothing here watches for that
automatically. Either watch
[nixpkgs#377136](https://github.com/NixOS/nixpkgs/issues/377136) directly for
a close/fix-landed comment, check `python-matter-server`'s release notes
after a `nix flake update` pulls a newer version (the real fix is either it
catching `ValueError` around cert parsing, not just `ClientError`/
`TimeoutError`, or `cryptography` relaxing its ASN.1 strictness for this
class of malformed cert), or periodically retest by temporarily dropping
`services.matter-server.package` back to the default and seeing if
`server.start()` completes against the live DCL fetch again.

**Trade-off**: no automatic pickup of PAA certs for newly-onboarded Matter
vendors. If commissioning a new device fails with a certificate/attestation
error and the device is legitimate, the pinned set is probably stale. To
re-pin:

1. Get a current commit: `git ls-remote https://github.com/project-chip/connectedhomeip.git refs/heads/master`.
2. Update `pinnedPaaCertsRev` in `modules/matter.nix` to that commit (and the
   date in its comment).
3. Set `hash = lib.fakeHash;` temporarily, run a build, and copy the real
   `sha256-...` hash from the mismatch error into `hash`.
4. Rebuild and redeploy.

Never regenerate or rotate anything Zigbee/Z-Wave-related to "fix" a Matter
problem — these are unrelated radio networks; see § Radio Networks § Both.
