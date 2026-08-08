# Pull request

## Summary

Why this change is needed. The diff already shows what changed — don't
restate it here.

Affected hosts: `enterprise-d` / `defiant` / `holodeck-01` / `excelsior` /
`reliant` / none.

## Test plan

One checklist, in the order to run it. Every step is a concrete, copyable
command in a fenced block with the expected result noted. "Verify it works"
is not a test step. Check a box only if you actually ran it and saw the
expected output; leave unchecked steps that need hardware, a host you can't
reach, or a state-changing command you must not run (`nixos-rebuild switch`,
`nix flake update`, a manual backup, the installer) — say who runs those in
the item.

- [ ] Lint and format

  ```bash
  nix develop -c pre-commit run --all-files
  ```

  Expected: every hook `Passed`.

- [ ] Flake evaluation — N/A if no `.nix` file changed (never bare
      `nix flake check`, it builds aarch64 on x86_64)

  ```bash
  nix flake check --no-build
  ```

  Expected: exits 0, no output.

- [ ] Host build, one per affected host — N/A if no `.nix` file changed

  ```bash
  nix build .#nixosConfigurations.enterprise-d.config.system.build.toplevel
  ```

  Expected: builds to `./result`.

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

Docs-only changes still run the Lint and format step above — it includes
markdownlint over every `.md` file. "Docs-only" only excuses the flake
evaluation and host build steps (marked N/A when no `.nix` file changed);
it never excuses lint.
