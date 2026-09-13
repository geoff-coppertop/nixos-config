#!/usr/bin/env python3
"""Reconcile declared Bambuddy printers and virtual printers over its REST API.

Bambuddy keeps its printer list and virtual-printer config in its own SQLite
database under DATA_DIR, and there is no seeding mechanism upstream: as of
v1.2.5.3 `backend/app/core/config.py` reads no seed file, no import path and
no printer-related environment variables (HA_URL / HA_TOKEN are the only
env-driven settings). Rows are created through the web UI or through the REST
API, and nothing else. So "declarative printers" can only mean talking to that
API after the service is up, which is what this script does.

CREATE-ONLY, DELIBERATELY. This script adds what is missing and touches
nothing else. It does not update and does not delete, and nobody should
"complete" it later by adding either:

  * The web UI is a legitimate place to change these settings. A reconciler
    that pushed the Nix values back over a UI edit would silently revert the
    user's work on the next timer tick, with no diff and no prompt.
  * A delete pass would destroy a printer row — and with it the archive
    association and print history keyed to it — because someone commented a
    line out of a Nix file.

Filling in what is absent is safe in a way that enforcing equality is not.

AUTH. Bambuddy's auth is opt-in: `is_auth_enabled()` in
`backend/app/core/auth.py` returns False when the `auth_enabled` settings row
is absent, which is the default, and every route here is guarded by
`RequirePermissionIfAuthEnabled`. This script therefore sends no credentials.
Turning auth on in Bambuddy's UI would break provisioning; the fix would be to
mint an API key (`backend/app/api/routes/api_keys.py`) and send it, not to
disable auth again.

Everything this script assumes about the API was read out of the upstream
source at tag v1.2.5.3; the specific file is cited next to each assumption.
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

# sysexits.h EX_TEMPFAIL. Separates "the declared state is not reachable yet"
# — printer powered off, access-code secret not deployed — from a real error,
# so `systemctl status` distinguishes the two without reading the journal.
EX_TEMPFAIL = 75
EX_FAILURE = 1

# Bambuddy's own printer probe (printer_manager.PROBE_TIMEOUT_SECONDS) is 8s,
# so a 30s client timeout leaves plenty of room for it plus TLS setup.
REQUEST_TIMEOUT_S = 30

# How long to wait for the app to answer /health before giving up and letting
# the timer retry. uvicorn is up in seconds, but the first start after an
# upgrade runs database migrations.
HEALTH_TIMEOUT_S = 180
HEALTH_POLL_S = 3

# Bambuddy is on this host, so an HTTP proxy must never be consulted for it.
# urllib's default opener reads http_proxy/no_proxy from the environment; an
# empty ProxyHandler removes that variable from the equation entirely.
_opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def info(message: str) -> None:
    print(message, flush=True)


def warn(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


def request(base_url: str, method: str, path: str, body=None):
    """Return (status, payload) for one API call. Never raises on HTTP status.

    `payload` is the decoded JSON body when the response is JSON, else the raw
    text. Errors below the HTTP layer (connection refused, DNS, timeout) come
    back as status 0 with the exception string as the payload, so callers can
    treat "not answering" the same way they treat any other retryable state.
    """
    data = None
    headers = {"Accept": "application/json"}
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"

    req = urllib.request.Request(
        base_url + path, data=data, headers=headers, method=method
    )

    try:
        with _opener.open(req, timeout=REQUEST_TIMEOUT_S) as resp:
            return resp.status, _decode(resp.read())
    except urllib.error.HTTPError as exc:
        return exc.code, _decode(exc.read())
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        return 0, str(exc)


def _decode(raw: bytes):
    text = raw.decode("utf-8", errors="replace")
    try:
        return json.loads(text)
    except ValueError:
        return text


def detail_of(payload) -> str:
    """Flatten FastAPI's `detail` into one line.

    POST /api/v1/printers/ raises two shapes of 400: a bare string for the
    duplicate-serial case and a dict {"code", "message"} for the
    connection-test failure (backend/app/api/routes/printers.py).
    """
    if isinstance(payload, dict):
        detail = payload.get("detail", payload)
        if isinstance(detail, dict):
            return str(detail.get("message") or detail.get("code") or detail)
        return str(detail)
    return str(payload)


def detail_code(payload) -> str:
    """The machine-readable `detail.code`, or "" when the detail is a string."""
    if isinstance(payload, dict):
        detail = payload.get("detail")
        if isinstance(detail, dict):
            return str(detail.get("code", ""))
    return ""


def wait_for_health(base_url: str) -> bool:
    """Poll the unprefixed /health route (backend/app/main.py) until it answers."""
    deadline = time.monotonic() + HEALTH_TIMEOUT_S
    last = ""
    while time.monotonic() < deadline:
        status, payload = request(base_url, "GET", "/health")
        if status == 200:
            return True
        last = f"HTTP {status}: {detail_of(payload)}"
        time.sleep(HEALTH_POLL_S)
    warn(f"Bambuddy did not answer {base_url}/health within "
         f"{HEALTH_TIMEOUT_S}s — last result: {last}")
    return False


def read_access_code(path: str) -> str | None:
    """Read a credential file, or return None with an explanation logged.

    A missing file is the normal state between "the option was set" and "the
    agenix secret was created and rekeyed", so it is reported as something to
    retry rather than as a hard error.
    """
    try:
        with open(path, encoding="utf-8") as handle:
            code = handle.read().strip()
    except OSError as exc:
        warn(f"  access-code file {path} is not readable yet ({exc.strerror}) "
             f"— skipping for now")
        return None

    if not code:
        warn(f"  access-code file {path} is empty — skipping for now")
        return None
    return code


def fetch_printers(base_url: str):
    """serial -> printer row. GET /api/v1/printers/ returns a bare JSON list."""
    status, payload = request(base_url, "GET", "/api/v1/printers/")
    if status != 200 or not isinstance(payload, list):
        warn(f"Could not list printers (HTTP {status}): {detail_of(payload)}")
        return None
    return {str(p.get("serial_number", "")).strip().upper(): p for p in payload}


def provision_printers(base_url: str, declared):
    """Create every declared printer that is absent. Returns (by_serial, pending, failed).

    The upstream route already refuses a duplicate serial before it does
    anything else, so the GET-first check here is about not making a pointless
    MQTT probe on every timer tick, not about correctness.
    """
    by_serial = fetch_printers(base_url)
    if by_serial is None:
        return None, 0, 1

    pending = 0
    failed = 0
    changed = 0

    for decl in declared:
        serial = decl["serialNumber"].strip().upper()
        name = decl["name"]

        if serial in by_serial:
            info(f"printer {name} ({serial}): already present")
            continue

        code = read_access_code(decl["accessCodeFile"])
        if code is None:
            warn(f"printer {name} ({serial}): pending — no access code")
            pending += 1
            continue

        body = {
            "name": name,
            "serial_number": serial,
            "ip_address": decl["ipAddress"],
            "access_code": code,
            "auto_archive": decl["autoArchive"],
        }
        for optional_field in ("model", "location"):
            if decl.get(optional_field) is not None:
                body[optional_field] = decl[optional_field]

        status, payload = request(base_url, "POST", "/api/v1/printers/", body)

        if status in (200, 201):
            info(f"printer {name} ({serial}): created")
            changed += 1
        elif status == 400 and "already exists" in detail_of(payload):
            # Raced with a UI add between the GET above and this POST.
            info(f"printer {name} ({serial}): already present")
            changed += 1
        elif status == 400 and detail_code(payload) == "printer_connection_failed":
            # Upstream verifies the MQTT connection to the real printer before
            # it will persist the row (backend/app/api/routes/printers.py), so
            # a powered-off or unreachable printer cannot be added at all.
            # That is the whole reason this runs on a timer.
            warn(f"printer {name} ({serial}): pending — Bambuddy could not "
                 f"reach it at {decl['ipAddress']}. Check that the printer is "
                 f"powered on, on the LAN, and in LAN Only + Developer Mode, "
                 f"and that the access code and serial are right.")
            pending += 1
        else:
            warn(f"printer {name} ({serial}): FAILED (HTTP {status}): "
                 f"{detail_of(payload)}")
            failed += 1

    # Re-read so the virtual-printer phase can resolve targetPrinterSerial
    # against rows created a moment ago in this same run.
    if changed:
        refreshed = fetch_printers(base_url)
        if refreshed is not None:
            by_serial = refreshed

    return by_serial, pending, failed


def provision_virtual_printers(base_url: str, declared, by_serial):
    """Create every declared virtual printer that is absent, matched by name."""
    # Unlike the printer route, this one returns an object:
    # {"printers": [...], "models": {code: display_name}}
    # (backend/app/api/routes/virtual_printers.py).
    status, payload = request(base_url, "GET", "/api/v1/virtual-printers")
    if status != 200 or not isinstance(payload, dict):
        warn(f"Could not list virtual printers (HTTP {status}): "
             f"{detail_of(payload)}")
        return 0, 1

    existing = {vp.get("name") for vp in payload.get("printers", [])}
    models = payload.get("models", {})
    # Upstream validates `model` against the KEYS of VIRTUAL_PRINTER_MODELS,
    # which are SSDP codes ("N7"), while the name a human knows is the value
    # ("P2S"). Resolving through the live `models` map instead of a table
    # copied into this repo means the accepted set cannot drift from the
    # running version. The inverse is lossy — two codes share "H2D Pro" and
    # two share "H2C" — and this is deliberately built the same way upstream
    # builds its own DISPLAY_NAME_TO_MODEL_CODE, last key wins, so a display
    # name resolves here to exactly what it resolves to there.
    code_of = {display: code for code, display in models.items()}

    pending = 0
    failed = 0

    for decl in declared:
        name = decl["name"]
        if name in existing:
            info(f"virtual printer {name}: already present")
            continue

        model = decl.get("model")
        if model is not None and model not in models:
            resolved = code_of.get(model)
            if resolved is None:
                warn(f"virtual printer {name}: FAILED — model {model!r} is "
                     f"neither a model code nor a model name known to this "
                     f"Bambuddy. Known: "
                     f"{', '.join(sorted(f'{c} ({d})' for c, d in models.items()))}")
                failed += 1
                continue
            model = resolved

        target_id = None
        target_serial = decl.get("targetPrinterSerial")
        if target_serial is not None:
            target = by_serial.get(target_serial.strip().upper())
            if target is None:
                warn(f"virtual printer {name}: pending — its target printer "
                     f"{target_serial} does not exist in Bambuddy yet")
                pending += 1
                continue
            target_id = target["id"]

        code = None
        if decl.get("accessCodeFile") is not None:
            code = read_access_code(decl["accessCodeFile"])
            if code is None:
                warn(f"virtual printer {name}: pending — no access code")
                pending += 1
                continue

        body = {
            "name": name,
            "enabled": decl["enabled"],
            "mode": decl["mode"],
            "auto_dispatch": decl["autoDispatch"],
            "queue_force_color_match": decl["queueForceColorMatch"],
            "save_ams_mapping": decl["saveAmsMapping"],
            "gcode_injection": decl["gcodeInjection"],
        }
        if model is not None:
            body["model"] = model
        if code is not None:
            body["access_code"] = code
        if target_id is not None:
            body["target_printer_id"] = target_id
        if decl.get("bindIp") is not None:
            body["bind_ip"] = decl["bindIp"]
        if decl.get("remoteInterfaceIp") is not None:
            body["remote_interface_ip"] = decl["remoteInterfaceIp"]

        status, payload = request(
            base_url, "POST", "/api/v1/virtual-printers", body
        )

        if status in (200, 201):
            info(f"virtual printer {name}: created")
        else:
            warn(f"virtual printer {name}: FAILED (HTTP {status}): "
                 f"{detail_of(payload)}")
            failed += 1

    return pending, failed


def main() -> int:
    if len(sys.argv) != 2:
        warn(f"usage: {os.path.basename(sys.argv[0])} <spec.json>")
        return EX_FAILURE

    with open(sys.argv[1], encoding="utf-8") as handle:
        spec = json.load(handle)

    base_url = spec["baseUrl"]

    if not wait_for_health(base_url):
        return EX_TEMPFAIL

    by_serial, pending, failed = provision_printers(base_url, spec["printers"])
    if by_serial is None:
        return EX_FAILURE

    vp_pending, vp_failed = provision_virtual_printers(
        base_url, spec["virtualPrinters"], by_serial
    )
    pending += vp_pending
    failed += vp_failed

    if failed:
        warn(f"{failed} declared item(s) could not be created and will not "
             f"succeed on retry without a config or secret change; "
             f"{pending} still pending.")
        return EX_FAILURE

    if pending:
        warn(f"{pending} declared item(s) not reconciled yet — retrying on "
             f"the next timer tick.")
        return EX_TEMPFAIL

    info("All declared printers and virtual printers are present.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
