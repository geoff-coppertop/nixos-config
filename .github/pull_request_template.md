# Pull request

## Summary

Why this change is needed. The diff already shows what changed — don't
restate it here.

Affected hosts: `enterprise-d` / `holodeck-01` / `excelsior` / `reliant` /
none.

## Test plan

One checklist, in the order to run it. Every step except the CI item is a
concrete, copyable command in a fenced block with the expected result noted. "Verify it works"
is not a test step. Check a box only if you actually ran it and saw the
expected output; leave unchecked steps that need hardware, a host you can't
reach, or a state-changing command you must not run (`nixos-rebuild switch`,
`nix flake update`, a manual backup, the installer) — say who runs those in
the item.

- [ ] Lint, flake evaluation and host builds — CI. Check this once CI is green on the head commit; no local command.

- [ ] Change-specific check

  ```bash
  # command
  ```

  Expected:

  ```text
  # output
  ```

- [ ] Apply on the target host — user, needs the physical/reachable host

  ```bash
  sudo nixos-rebuild switch --flake .#enterprise-d
  ```

  Expected: switch completes; `systemctl --failed` is empty.

- [ ] Hardware or host-specific verification — user

  ```bash
  # command
  ```

  Expected:

  ```text
  # output
  ```

Docs-only changes are covered the same way: markdownlint runs over every `.md`
file in the CI lint job.
