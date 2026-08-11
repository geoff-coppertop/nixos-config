#!/usr/bin/env python3
"""
check_ha_entities.py

Check that every entity_id a Nix-declared Home Assistant automation
references under hosts/<host>/home-assistant/*.nix actually exists in that
host's live entity registry.

This is the automated version of the manual check docs/smart-home.md already
asks for: "Verify entity IDs before writing them ... a wrong ID produces an
automation that loads cleanly and silently never fires." It catches a stale
or mistyped entity_id (e.g. after re-pairing a device, or migrating to a
fresh HA instance) that would otherwise fail silently.

What it checks:
  - Every entity_id string literal referenced by hosts/*/home-assistant/*.nix,
    for the given host, against the entity_ids registered in that host's live
    Home Assistant instance (read from
    /var/lib/hass/.storage/core.entity_registry over SSH).

What it can't catch (see docs/smart-home.md § Automated entity ID check for
detail): entity IDs that only exist at runtime as the value of a Nix
variable or function argument rather than as a literal string in the file —
for example presence-lighting.nix's `mkPresenceLighting` takes `presence`
and `lights` as function parameters; the *call site* passing the literal
strings is still parsed correctly, but if a future refactor sources those
values from somewhere other than a literal (a shared list, an import, etc.)
this tool will silently miss them. It does not evaluate Nix; it greps for
string literals that look like <domain>.<object_id> and independently for
`entity_id = "...";` / `target.entity_id = "...";`.

Usage:
  python3 tools/check_ha_entities.py <host> [--host-dir hosts/<host>]

  <host>        SSH target (see lib/ssh-hosts.nix for the pinned aliases,
                e.g. "defiant", "defiant.local", "reliant", "reliant.local").
                Also used as the default hosts/<host>/home-assistant
                directory name unless --host-dir overrides it.

Exit status:
  0   every referenced entity_id was found in the live registry
  1   at least one referenced entity_id is missing from the live registry, or
      a usage/environment error occurred (bad path, SSH failure, unparseable
      registry — see tools/common.py's die())
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from common import die, repo_root

# entity_id form: <domain>.<object_id>, both lowercase snake_case segments.
# Matches things like "lock.front_door" or "binary_sensor.geoff_s_office_presence_occupancy".
ENTITY_ID_RE = re.compile(r"\b[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\b")

# Domains that appear in service calls (e.g. "lock.lock", "switch.turn_on")
# but are never entity IDs themselves. Filtered out because ENTITY_ID_RE
# can't distinguish a service call string from an entity_id string on shape
# alone.
SERVICE_CALL_SUFFIXES = {
    "turn_on",
    "turn_off",
    "lock",
    "unlock",
    "toggle",
    "open",
    "close",
    "set_state",
    "reload",
}

REGISTRY_PATH = "/var/lib/hass/.storage/core.entity_registry"

# Domains that are set up via a bare YAML platform (no config entry, no
# unique_id) rather than an integration that registers into
# core.entity_registry. These entities are real and work fine, but never
# appear in the registry, so they'd always false-positive as "missing" here.
# "sun" is the only one this repo's automations reference today — see
# modules/home-assistant.nix's `sun = {}` and docs/smart-home.md.
NON_REGISTRY_DOMAINS = {"sun"}


def extract_declared_entity_ids(home_assistant_dir: Path) -> dict[str, set[Path]]:
    """Scan hosts/<host>/home-assistant/*.nix for entity_id string literals.

    Returns a mapping of entity_id -> set of files it was found in.

    Deliberately conservative: this is a grep over string literals, not a
    Nix evaluator. It reliably finds entity IDs written directly as strings
    (the `target.entity_id = [ "lock.front_door" ]` list form, and the bare
    `entity_id = "sun.sun";` trigger/condition form). It cannot resolve an
    entity_id that only appears at a call site through a Nix variable or
    function parameter unless that call site itself passes a literal string
    (which is the case for every automation in this repo today, including
    presence-lighting.nix's mkPresenceLighting calls).
    """
    found: dict[str, set[Path]] = {}
    for nix_file in sorted(home_assistant_dir.glob("*.nix")):
        text = nix_file.read_text()
        # Only look inside quoted string literals, so we don't pick up
        # arbitrary dotted identifiers from comments or Nix syntax such as
        # `lib.splitString`.
        for match in re.finditer(r'"([^"\n]*)"', text):
            candidate = match.group(1)
            if not ENTITY_ID_RE.fullmatch(candidate):
                continue
            domain, _, object_id = candidate.partition(".")
            if object_id in SERVICE_CALL_SUFFIXES:
                continue
            found.setdefault(candidate, set()).add(nix_file)
    return found


def fetch_registry_entity_ids(host: str) -> set[str]:
    """SSH to `host` and read the live entity_id set from the entity registry.

    Uses `sudo cat` because /var/lib/hass is owned by the hass service user,
    not the SSH login user. Relies on the same SSH host-key pinning used for
    every other manual admin command against hosts in lib/ssh-hosts.nix.
    """
    cmd = ["ssh", host, "sudo", "cat", REGISTRY_PATH]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        die(
            f"failed to read {REGISTRY_PATH} on {host} over SSH "
            f"(exit {result.returncode}): {result.stderr.strip()}"
        )

    try:
        registry = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        die(f"could not parse {REGISTRY_PATH} from {host} as JSON: {exc}")

    try:
        entities = registry["data"]["entities"]
    except (KeyError, TypeError):
        die(
            f"{REGISTRY_PATH} on {host} did not have the expected "
            "top-level {'data': {'entities': [...]}} shape"
        )

    entity_ids = set()
    for entity in entities:
        entity_id = entity.get("entity_id")
        if entity_id:
            entity_ids.add(entity_id)
    return entity_ids


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Check Nix-declared Home Assistant automation entity_ids "
            "against the live entity registry on a host."
        )
    )
    parser.add_argument(
        "host",
        help=(
            "SSH target for the running Home Assistant instance "
            "(see lib/ssh-hosts.nix), e.g. defiant or reliant."
        ),
    )
    parser.add_argument(
        "--host-dir",
        help=(
            "Override the hosts/<host>/home-assistant directory to scan "
            "(default: derived from <host>, e.g. hosts/defiant/home-assistant)."
        ),
    )
    parser.add_argument(
        "--show-unreferenced",
        action="store_true",
        help=(
            "Also list live registry entities that look related to the "
            "domains used by declared automations but aren't referenced by "
            "any of them. Informational only, never affects exit status."
        ),
    )
    args = parser.parse_args()

    root = repo_root()
    if root is None:
        die("must be run from within the nixos-config git repository")

    if args.host_dir:
        home_assistant_dir = Path(args.host_dir)
        if not home_assistant_dir.is_absolute():
            home_assistant_dir = root / home_assistant_dir
    else:
        # SSH aliases like "reliant.local" (see lib/ssh-hosts.nix) share the
        # same hosts/<host>/home-assistant directory as the bare hostname.
        host_dir_name = args.host.split(".", 1)[0]
        home_assistant_dir = root / "hosts" / host_dir_name / "home-assistant"

    if not home_assistant_dir.is_dir():
        die(f"{home_assistant_dir} is not a directory")

    declared = extract_declared_entity_ids(home_assistant_dir)
    if not declared:
        die(f"found no entity_id string literals under {home_assistant_dir}")

    live_entity_ids = fetch_registry_entity_ids(args.host)

    skipped = sorted(
        eid for eid in declared if eid.split(".", 1)[0] in NON_REGISTRY_DOMAINS
    )
    checked = {eid: files for eid, files in declared.items() if eid not in skipped}
    missing = sorted(set(checked) - live_entity_ids)

    print(
        f"Checked {len(checked)} entity_id(s) referenced under "
        f"{home_assistant_dir} against {len(live_entity_ids)} live entities "
        f"on {args.host} ({REGISTRY_PATH})."
    )
    if skipped:
        print(
            f"Skipped {len(skipped)} entity_id(s) in non-registry domains "
            f"(never appear in {REGISTRY_PATH} even when working correctly): "
            + ", ".join(skipped)
        )

    if missing:
        print(
            f"\n{len(missing)} referenced entity_id(s) NOT found in the live "
            "registry:",
            file=sys.stderr,
        )
        for entity_id in missing:
            files = ", ".join(sorted(p.name for p in declared[entity_id]))
            print(f"  {entity_id}  (referenced in {files})", file=sys.stderr)
    else:
        print("All referenced entity_ids exist in the live registry.")

    if args.show_unreferenced:
        declared_domains = {eid.split(".", 1)[0] for eid in declared}
        unreferenced = sorted(
            eid
            for eid in live_entity_ids
            if eid.split(".", 1)[0] in declared_domains and eid not in declared
        )
        if unreferenced:
            print(
                f"\n{len(unreferenced)} live entity_id(s) in the same domains "
                "as declared automations but not referenced by any of them "
                "(informational only):"
            )
            for entity_id in unreferenced:
                print(f"  {entity_id}")

    sys.exit(1 if missing else 0)


if __name__ == "__main__":
    main()
