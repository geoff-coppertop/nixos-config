#!/usr/bin/env python3
"""
deploy_all.py

Build every machine in the flake, then switch the reachable ones, from a single
command.

The host list is not written down here. It is read out of the flake
(`nixosConfigurations`), the same way tools/ci_changed_hosts.py does it, so
registering a host in flake.nix is the only step needed for it to be deployed —
there is no second list to remember.

Everything is built before anything is switched. A host that fails to evaluate
or build aborts the whole run with no machine touched, so a broken commit can't
leave half the fleet on a new generation and half on the old one.

Remotable hosts are probed for reachability *before* the build loop, and an
unreachable one is neither built nor switched — its closure can't be applied
this run, so building it is wasted work. The probe is an SSH command rather
than a ping or a TCP connect because it exercises the exact path
`nixos-rebuild --target-host` uses, auth included: a host that answers pings
but has sshd down, a stale host key, or no usable key for `thomasga` is
correctly reported unreachable instead of passing a shallower check.

Each remotable host is probed with `ssh <target> sudo -n true` before the
switch, and `--sudo` or `--ask-sudo-password` is picked from that result up
front. A host is never retried after the real switch fails: `nixos-rebuild
switch` exits nonzero both when sudo itself fails *and* when elevation
succeeded but a downstream systemd unit failed to (re)start, and those are
different problems — the second is a real deployment failure, not a privilege
issue, and retrying it only re-runs the entire switch (redecrypting secrets,
restarting every changed unit again) to hit the same failure again, while
also prompting for a password that was never the actual cause.

Usage:
    python3 tools/deploy_all.py [--dry-run] [--yes]
                                [--only h1,h2] [--skip h1,h2] [--skip-checks]
"""

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from common import ci_log, die, nix_eval_json, repo_root

# Hosts with no SSH-reachable remote path, deployed by hand on the machine
# itself. holodeck-01 is a WSL distro: it has no mDNS name and no sshd, which
# is why docs/operations.md gives it no `--target-host` invocation either.
LOCAL_ONLY = {"holodeck-01"}

# Matches the per-host table in docs/operations.md.
REMOTE_USER = "thomasga"

# Ceiling for the whole probe, in case ssh hangs past its own ConnectTimeout.
SSH_PROBE_TIMEOUT = 15


def remote_target(host: str) -> str:
    return f"{REMOTE_USER}@{host}.local"


def manual_command(host: str, action: str) -> str:
    return f"sudo nixos-rebuild {action} --flake .#{host}"


def remote_command(host: str, action: str, ask_password: bool = False) -> list[str]:
    return [
        "nixos-rebuild",
        action,
        "--flake",
        f".#{host}",
        "--target-host",
        remote_target(host),
        "--ask-sudo-password" if ask_password else "--sudo",
    ]


def host_names(root: Path) -> list[str]:
    """Every host registered in the flake's nixosConfigurations."""
    names = nix_eval_json(".#nixosConfigurations", "builtins.attrNames", root)
    if not isinstance(names, list) or not names:
        die("could not enumerate nixosConfigurations — refusing to guess a host list")
    return sorted(names)


def parse_list(value: str | None) -> set[str]:
    if not value:
        return set()
    return {item.strip() for item in value.split(",") if item.strip()}


def select_hosts(names: list[str], only: set[str], skip: set[str]) -> list[str]:
    unknown = (only | skip) - set(names)
    if unknown:
        die(f"unknown host(s): {', '.join(sorted(unknown))}")
    selected = [n for n in names if (not only or n in only) and n not in skip]
    if not selected:
        die("no hosts left to deploy after applying --only/--skip")
    return selected


def run_checks(root: Path) -> bool:
    ci_log("Running pre-commit over the whole tree...")
    result = subprocess.run(
        ["nix", "develop", "-c", "pre-commit", "run", "--all-files"],
        cwd=str(root),
    )
    return result.returncode == 0


def build_host(host: str, root: Path) -> bool:
    ci_log(f"{host}: building toplevel...")
    result = subprocess.run(
        [
            "nix",
            "build",
            f".#nixosConfigurations.{host}.config.system.build.toplevel",
            "--no-link",
        ],
        cwd=str(root),
    )
    return result.returncode == 0


def host_reachable(host: str, root: Path) -> bool:
    ci_log(f"{host}: probing {remote_target(host)} over SSH...")
    try:
        result = subprocess.run(
            [
                "ssh",
                "-o",
                "BatchMode=yes",
                "-o",
                "ConnectTimeout=5",
                remote_target(host),
                "true",
            ],
            capture_output=True,
            text=True,
            cwd=str(root),
            timeout=SSH_PROBE_TIMEOUT,
        )
    except subprocess.TimeoutExpired:
        ci_log(f"{host}: unreachable — ssh probe timed out after {SSH_PROBE_TIMEOUT}s")
        return False
    if result.returncode != 0:
        detail = result.stderr.strip().splitlines()
        reason = detail[-1] if detail else f"ssh exit {result.returncode}"
        ci_log(f"{host}: unreachable — {reason}")
        return False
    return True


def sudo_passwordless(host: str, root: Path) -> bool:
    """True if the target's currently-running system lets REMOTE_USER sudo
    with no password. Checked directly, up front, rather than inferred from
    whether the real switch command fails — that exit code is also nonzero
    when elevation worked fine but a systemd unit failed downstream."""
    try:
        result = subprocess.run(
            [
                "ssh",
                "-o",
                "BatchMode=yes",
                "-o",
                "ConnectTimeout=5",
                remote_target(host),
                "sudo",
                "-n",
                "true",
            ],
            capture_output=True,
            text=True,
            cwd=str(root),
            timeout=SSH_PROBE_TIMEOUT,
        )
    except subprocess.TimeoutExpired:
        return False
    return result.returncode == 0


def confirm(host: str) -> bool:
    answer = input(f"Switch {host} now? [y/N] ").strip().lower()
    return answer in {"y", "yes"}


def summarise(
    built: list[str],
    applied: list[str],
    skipped: list[str],
    failed: list[str],
    unreachable: list[str],
    applied_label: str = "switched",
) -> None:
    def line(label: str, hosts: list[str]) -> str:
        return f"  {label:<14}{', '.join(hosts) if hosts else '-'}"

    print("Deployment summary")
    print(line("built", built))
    print(line(applied_label, applied))
    print(line("skipped", skipped))
    print(line("unreachable", unreachable))
    print(line("failed", failed))


def main() -> None:
    parser = argparse.ArgumentParser(description="Build every host, then switch the reachable ones.")
    parser.add_argument("--dry-run", action="store_true", help="dry-activate instead of switching")
    parser.add_argument("-y", "--yes", action="store_true", help="do not prompt before each switch")
    parser.add_argument("--only", help="comma-separated hosts to deploy (default: all)")
    parser.add_argument("--skip", help="comma-separated hosts to leave alone")
    parser.add_argument(
        "--skip-checks",
        action="store_true",
        help="skip the pre-commit pre-flight (not recommended)",
    )
    args = parser.parse_args()

    root = repo_root()
    if root is None:
        die("not in a git repo — run this from the nixos-config checkout")

    names = host_names(root)
    ci_log(f"Hosts in flake: {', '.join(names)}")

    # Validate the filters before the pre-flight and the builds, so a typo'd
    # host name costs a second rather than a full fleet build.
    selected = select_hosts(names, parse_list(args.only), parse_list(args.skip))

    if args.skip_checks:
        ci_log("Skipping pre-commit pre-flight (--skip-checks).")
    elif not run_checks(root):
        die("pre-commit failed — fix it or re-run with --skip-checks")

    unreachable = [h for h in names if h not in LOCAL_ONLY and not host_reachable(h, root)]
    if unreachable:
        ci_log(f"Unreachable this run, neither built nor switched: {', '.join(unreachable)}")
    named_unreachable = sorted(parse_list(args.only) & set(unreachable))
    if named_unreachable:
        ci_log(f"--only named unreachable host(s): {', '.join(named_unreachable)}")
        if not [h for h in selected if h not in unreachable]:
            die("every host named by --only is unreachable — nothing to build or switch")

    # Build the whole fleet, not just the selected hosts: a change that breaks
    # a host excluded by --only is still a change that shouldn't be deployed.
    # Unreachable hosts are the one exclusion — they can't be switched this run,
    # so their closure would be built for nothing.
    built: list[str] = []
    failed: list[str] = []
    for host in [h for h in names if h not in unreachable]:
        if build_host(host, root):
            built.append(host)
        else:
            failed.append(host)
    if failed:
        summarise(built, [], [], failed, unreachable)
        die(f"build failed for {', '.join(failed)} — nothing was switched")

    remotable = [h for h in selected if h not in LOCAL_ONLY and h not in unreachable]
    manual = [h for h in names if h in LOCAL_ONLY]
    action = "dry-activate" if args.dry_run else "switch"

    switched: list[str] = []
    skipped: list[str] = [h for h in names if h not in remotable and h not in unreachable]

    for host in remotable:
        if not args.dry_run and not args.yes and not confirm(host):
            ci_log(f"{host}: declined — skipping.")
            skipped.append(host)
            continue
        ask_password = not sudo_passwordless(host, root)
        if ask_password:
            ci_log(f"{host}: no passwordless sudo — you will be prompted locally.")
        ci_log(f"{host}: nixos-rebuild {action} via {remote_target(host)}...")
        result = subprocess.run(
            remote_command(host, action, ask_password=ask_password), cwd=str(root)
        )
        if result.returncode == 0:
            switched.append(host)
        else:
            failed.append(host)
            ci_log(f"{host}: nixos-rebuild {action} failed (exit {result.returncode}).")

    summarise(
        built,
        switched,
        sorted(set(skipped)),
        failed,
        unreachable,
        applied_label="dry-activated" if args.dry_run else "switched",
    )

    for host in manual:
        print(
            f"\n{host} has no remote path — run this inside the WSL distro:\n"
            f"  {manual_command(host, action)}"
        )

    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
