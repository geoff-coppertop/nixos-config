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
frontend port (8123) closed to everything except a narrow LAN carve-out,
with all other access going through Traefik — is unchanged and is carried
entirely by `hosts/reliant/configuration.nix`'s
`networking.firewall.extraCommands` iptables rule(s) and the Traefik route
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
└── presence-lighting.nix # presence-driven room lighting
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
does this for per-room presence lighting. Its `mkPresenceLighting` also takes
an optional `door` binary_sensor (a Zigbee Parasoll contact sensor, wired in
for the Utility Room): when set, the door opening becomes an extra "instant
on" trigger. On the off side, `door` doesn't gate the same way — motion
alone still decides *that* lights should go off — but it does change *how
long that takes*: a second, template-based trigger fires `doorClosedLinger`
(a short wait, e.g. one minute) after presence has cleared and the door has
also closed, for the "left and shut the door behind them" case, while the
plain `presence -> off, for = linger` trigger remains as the longer
max/fallback wait that fires regardless of door state, so propping the door
open doesn't keep the lights on indefinitely.

That last guarantee is why the `choose` action dispatches on *which trigger
fired* (`condition: trigger, id: [...]`, matched against an `id` set on every
trigger) instead of re-checking current presence/door state on every firing:
re-checking state would mean a still-open door reads as "on" right as the
`linger` fallback fires, sending that firing to the on-branch and the lights
would never turn off — confirmed live on `reliant` (lights stuck on past
both `linger` and `doorClosedLinger` with the door propped open) before this
dispatch was added. Only the `homeassistant` start trigger, which isn't
tied to a specific on/off edge, falls through to a current-state check, to
restore the correct state after a reboot. `kids-wake-lights.nix` extends the
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

**Naming convention**: an automation's `alias` is `"Area: lowercase
description"` (colon separator, e.g. `"Outside Lights: arrival/departure
(when dark)"`) — not an em dash and not a bare sentence with no area prefix.
Its `id` is `area_slug_description`, prefixed to match the file's concern
(`sonos_*`, `climate_*`, `door_locks_*`, `outside_lights_*`,
`kids_wake_lights_*`, `presence_lighting_*`, `appletv_geoffs_office_*`), so ids stay
grep-able back to their file even after they're merged into one list. The
same `"Area: description"` shape also applies to the `name` of any
input_boolean/input_number/input_text/timer helper backing an automation
(e.g. `"Climate: summer mode"`, `"Main/basement: winter day"`) — helpers and
their automations show up side by side in the HA UI, so they should read as
one naming system, not two. Follow this for any new automation or helper.

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

Core HA's `linkplay` integration still can't drive the Wiim Pro units
usefully (see below), but `"linkplay"` is in `extraComponents`: without it,
zeroconf/SSDP discovery finding the Wiim speaker on the LAN triggered an
unhandled `ModuleNotFoundError` from HA's loader every boot (confirmed live
— a full traceback in `journalctl`, not a caught error).

`getMetaInfo` returning the literal string `"Failed"` instead of JSON
(`home-assistant/core#145132`) was a real bug, but it's already fixed at
this flake's pinned nixpkgs revision (`ffb3c9b7`, `python-linkplay` 0.2.14,
`home-assistant` 2026.8.2): `LinkPlayPlayer.update_status` catches exactly
this case and returns empty metainfo instead of raising (verified against
both packages' source at that revision), so `linkplay/config_flow.py`'s
zeroconf step reaches its `manufacturer == MANUFACTURER_WIIM` check and
aborts cleanly (`not_linkplay_device`) with no exception at all. So adding
the dependency doesn't trade one crash for another here — confirmed live
on `reliant`: no `ModuleNotFoundError` or any other `linkplay`-related
exception in `journalctl` after redeploying with it added.

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

### OIDC Login (Authelia SSO)

Home Assistant deliberately does **not** sit behind the `authelia@file`
forward-auth middleware that gates several other reliant subdomains
(`dns1`, `dns2`, `zigbee`, `dcs`, `dcs-control`, `bambuddy`) — it already has
its own real login, so forward-auth would just add a redundant second login
screen in front of it, not actual SSO. Instead, Authelia also runs as an
OpenID Connect 1.0 provider (`custom.authelia.oidc`,
[docs/homelab-network.md § OIDC Provider](homelab-network.md#oidc-provider)
— homelab-network's module and doc, not this one), and Home Assistant is
registered as its one OIDC client. This section is the other half: making
Home Assistant actually use it. See that doc for the provider-side design
(the two provider-level secrets, the client registration, and why the raw
client secret has to be generated outside this repo's Authelia config).

`custom.home-assistant.oidc` (`modules/home-assistant.nix`):

- `enable` renders hass-oidc-auth's `auth_oidc:` configuration.yaml block.
  It does **not** install the component itself — see § HACS Components
  below for that half.
- `clientId` (default `home-assistant`) and `discoveryUrl` (default composed
  from `custom.authelia.subdomain` and `custom.traefik.acme.domain`) both
  have real, usable defaults, mirroring `custom.authelia.oidc.homeAssistant`'s
  own defaults on the provider side — the two must agree, and matching
  literal defaults on both sides is how that's kept true without one module
  depending on the other's internals.
- `clientSecretFile` — the one required value, and the one genuine
  blocker: hass-oidc-auth's `auth_oidc.client_secret` needs the **raw**
  shared secret, while Authelia's config only ever stores a pbkdf2-sha512
  hash of it (see the homelab-network doc's client-secret explanation).
  There is no existing secret for this — see hosts/reliant/README.md
  § Secrets for exactly what `secrets-warden` needs to create.
  Wired as an `EnvironmentFile` (read by systemd itself as root, same
  mechanism as `locationEnvFile` above) exposed via HA's own `!env_var` YAML
  tag as `HASS_OIDC_CLIENT_SECRET`, rather than hass-oidc-auth's own
  documented `!secret`/`secrets.yaml` route — kept consistent with this
  repo's one existing secret-wiring convention for `configuration.yaml`
  instead of introducing a second one. Multiple `EnvironmentFile` entries
  (this one and `locationEnvFile`'s) coexist because each is contributed as
  a single-element list rather than a bare string — nixpkgs' systemd
  freeform "unit option" type concat-merges list-valued definitions of the
  same key instead of requiring separate definitions to be equal, which
  only applies when every definition given is itself a list.

- `defaultRedirect` (default `false`, `true` on `reliant`) — hass-oidc-auth's
  `auth_oidc.features.default_redirect`. Without it, visiting
  `home.coppertop.ca` shows HA's normal login page with an extra OIDC
  button next to the local form — not real SSO, just an option. With it,
  visiting the page skips straight to Authelia's login. Local login stays
  reachable as a fallback via `?skip_oidc_redirect=true` on the login URL —
  worth remembering before enabling this, since it's the only way back in
  if Authelia is ever down.

Config schema (`client_id`, `client_secret`, `discovery_url`, and the rest)
confirmed directly against hass-oidc-auth's own
[YAML Configuration Guide](https://github.com/christiaangoossens/hass-oidc-auth/blob/main/docs/configuration.md)
and [Authelia provider guide](https://github.com/christiaangoossens/hass-oidc-auth/blob/main/docs/provider-configurations/authelia.md)
— not guessed, and not the same field names as an earlier design pass might
suggest (no `issuer`, no `redirect_uri` on HA's own side — hass-oidc-auth
derives its callback from HA's own base URL and only Authelia's client
registration needs the literal redirect URI).

### HACS Components: `customComponents`, not a HACS runtime install

hass-oidc-auth is HACS-distributed, third-party, and not part of Home
Assistant core, so nixpkgs' `component-packages.nix` has no entry for it and
`extraComponents` can't install it — the same gap `wiim` (above) already hit
and solved. `pkgs/home-assistant-oidc-auth.nix` packages it the same way,
via `buildHomeAssistantComponent`, wired in through
`services.home-assistant.customComponents` in the host's `configuration.nix`
rather than a HACS runtime install inside the running instance: this repo
has no mechanism (and none is added here) for installing HACS itself or
letting it manage components at runtime — every third-party Home Assistant
integration in this repo is packaged declaratively this way instead, so a
fresh install carries every custom component from first boot rather than
depending on a manual HACS setup step post-install.

Its `requirements` (manifest.json's `aiofiles`, `jinja2`, `joserfc`) are
handled the same way `pywiim` was for `wiim`: `jinja2` is already a hard
dependency of Home Assistant core itself, so it needs no entry; `aiofiles`
and `joserfc` both already exist as ordinary top-level nixpkgs
`python-modules` (confirmed against nixpkgs' own tree), so — unlike
`pywiim`, which nixpkgs didn't have at all — they resolve directly off
`home-assistant.python3Packages` with no separate package file needed.

List every `manifest.json` requirement in `dependencies`, even ones HA core
already has: `manifestCheckPhase` checks this derivation, not the merged
environment. `jinja2` and `aiohttp` each failed a build on that assumption.

### Bambuddy

Bambuddy publishes no HA Discovery messages, so
`pkgs/home-assistant-bambuddy.nix` packages
[`Spegeli/hacs_bambuddy`](https://github.com/Spegeli/hacs_bambuddy) — pinned
to a tag, since upstream calls it "not intended for production use".

`config_flow`-only: after a rebuild add it (`127.0.0.1`,
`custom.bambuddy.port`, any non-empty API key), then **Configure > Add
printer** per printer — printers are in the options flow, not the initial one.

### Discovery-flow `ModuleNotFoundError`s: `cast`, `ecobee`, `ipp`, `linkplay`, `zha`

Zeroconf/SSDP discovery kept finding five real devices on the LAN (a Wiim
speaker, a Chromecast, the ecobee thermostats, a network printer, the Zigbee
coordinator) and offering their core integration's config flow, which then
crashed with an unhandled `ModuleNotFoundError` — a full traceback in
`journalctl`, not a caught warning — because the dependency wasn't in
`extraComponents`. A missing dependency only blocks the flow from
*initializing*; it has no bearing on whether the integration gets configured
or on whatever the flow does once it can actually run (cloud credentials,
confirming a coordinator claim, or its own unrelated failure). All five get
the dependency added, `linkplay` included — its own past failure mode
(`getMetaInfo` returning "Failed") is already fixed at this flake's pinned
nixpkgs revision, see § Wiim below.

- **`cast`** (`pychromecast`) / **`ipp`** (`pyipp`) — real new capabilities,
  wanted. Added to `extraComponents`.
- **`ecobee`** (`python-ecobee-api` — differs from the journal's `pyecobee`)
  — added. Nobody will complete its config flow (HomeKit already controls
  both thermostats via `ecobee-climate.nix`; ecobee also closed developer-key
  signups), so the discovered card just gets Ignore'd.
- **`zha`** — added. Checked HA core's own `zha/config_flow.py` (2026.8.2):
  the coordinator's serial port only opens on confirming the flow, not on
  discovery/rendering the card. So there's no port conflict with the
  already-adopted Zigbee2MQTT (`custom.zigbee`) from adding the dependency —
  the conflict is avoided by never confirming, same as `ecobee`.
- **`linkplay`** — added. Its zeroconf step probes the device (`getMetaInfo`)
  unconditionally; against these Wiim Pro units that used to raise
  (`home-assistant/core#145132`), but both sides of the fix are already in
  this flake's pinned nixpkgs revision (§ Wiim below), so the probe now
  aborts cleanly instead of raising. Core `linkplay` still won't drive the
  device (the community `wiim` integration is the real fix for control),
  but nothing here should reach the journal as an exception.

Resolution for `ecobee`/`zha`: **Settings → Devices & Services → find the
discovered card → Ignore.** One-time, survives reboots.

### Geoff's Office AV: CEC handles volume, not power

The Apple TV in Geoff's Office (`media_player.apple_tv_geoff_s_office`) feeds a Yamaha
HTR-4063 receiver, which feeds a projector, both over HDMI. Confirmed live,
CEC (Apple TV Settings > Remotes and Devices > Volume Control > Auto, with
HDMI Control enabled on the receiver) correctly handles volume for this
chain — no Home Assistant or Nix config involved. Also confirmed live, CEC
does **not** cascade power on this hardware: putting the Apple TV to sleep
does not power off the receiver or the projector, even though the Apple TV
is CEC-wired directly to the receiver rather than through the projector — so
this isn't a pass-through gap, CEC power simply doesn't propagate here.

`hosts/reliant/home-assistant/appletv-av.nix` drives power instead, via IR
commands sent through a Broadlink RM4 mini (`broadlink` component, already in
`extraComponents`), entity `remote.geoff_s_office_wi_fi_universal_remote`,
whenever the Apple TV's `media_player` state transitions between off/standby
and an active state.

A third automation in the same file is an independent vacancy safety net:
if `binary_sensor.geoff_s_office_presence_occupancy` (the same Aqara FP1e
sensor `presence-lighting.nix` uses for this room's lights, at a 5-minute
linger there) shows no presence for 20 minutes, it puts the Apple TV to
sleep and sends both devices' PowerOff codes regardless of Apple TV state.
The other two automations only react to the Apple TV's own state, so
leaving the room mid-playback without pausing or sleeping it would
otherwise never trigger a shutoff. Unconditional and not state-tracked —
overlapping with the Apple-TV-triggered power-off automation is harmless,
since a discrete PowerOff sent twice is a no-op.

All four commands (both devices' on and off) are baked into the Nix file as
raw `remote.send_command` `b64:` codes rather than referenced by
device/command name, even though the projector's remote has ordinary
discrete Power On/Standby buttons that `remote.learn_command` could capture
cleanly. A device/command name only resolves against whatever's been learned
into the RM4's own `.storage` on the running instance — that state isn't
declared anywhere, so a fresh Home Assistant instance (a reinstall, a lost
`/var/lib/hass`) would silently carry a broken automation until someone
remembered to manually re-learn all four commands. The projector's two codes
are exactly what `remote.learn_command` captured, copied out of storage
verbatim — see `hosts/reliant/README.md` § Device Pairing Notes for the
learning steps used to produce them. The receiver's required actual
reverse-engineering, covered next.

### Receiver power: reverse-engineered discrete NEC codes, not a learned toggle

The receiver's own remote has only a single power **toggle** button — no
discrete on/off exists to learn via `remote.learn_command`. Blindly sending
that same learned toggle for both "on" and "off" would desync Home
Assistant's assumed state from the receiver's real state the first time they
ever disagreed (e.g. after any manual power-button press), with no way to
detect or correct the drift — a Broadlink RM4 has no return channel, so it
never knows the receiver's actual state.

Confirmed live instead: the receiver's underlying NEC command table has
genuine discrete `PowerOn`/`PowerOff` codes, even though the stock remote
never exposes a button for them. Found by decoding a `remote.learn_command`
capture of the toggle button — NEC's address/complement-checksum structure
makes the address byte (`0x7E`) and the toggle's own command byte (`0x2A`)
recoverable with certainty, not a guess — then cross-referencing that against
a known Yamaha RX-V IR code table for the same address family, which listed
discrete `PowerOn = 0x7E` / `PowerOff = 0x7F` alongside a toggle command
byte that matched the decoded one almost exactly (off by one bit in a
transcription of that table, not a real mismatch, since a valid NEC
complement byte is always `0xFF ^ command` regardless of what the source
recorded). Both discrete codes were synthesized as raw NEC frames — reusing
the receiver's own captured timing and address bits, swapping only the
command byte — and tested directly against the hardware before trusting
them: `PowerOn` sent while off turned it on, `PowerOff` sent while on turned
it off and, sent again, left it off (ruling out a second toggle).

Because no remote button sends these, they can't be captured with
`remote.learn_command` — `appletv-av.nix` sends them via
`remote.send_command`'s raw-injection form (`command = "b64:...";` with no
`device`) instead of a learned device/command pair. If this receiver is ever
replaced, this whole derivation has to be redone from scratch for the new
unit's own address/command bytes — nothing here is portable to different
hardware, even another Yamaha model, without reverse-engineering it again.

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
