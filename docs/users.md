# Users And Home-Manager

How a user is attached to a machine, how to add one, and the three patterns for
managing their files.

Desktop application policy, desktop appearance, and workstation tooling live in
[docs/desktop.md](desktop.md).

## The User Model

A user is fully assigned to a machine only when two pieces are present:

1. A Unix account exists in the NixOS config.
2. A matching home-manager config is attached for that host.

Not all users exist on all machines. Each machine declares exactly which users it
has.

### Current example: `thomasga`

The system account is declared through `custom.users` in the host configuration.
`modules/users.nix` defines that option and turns each entry into a
`users.users.*` entry with `isNormalUser = true`:

```nix
# hosts/<machine>/configuration.nix
custom.users.thomasga =
  thomasga
  // {
    groups = ["wheel" "networkmanager"];
    avatar = null;
  };
```

The `thomasga` on the right is `users/thomasga/account.nix`, a plain attrset of
the machine-independent attributes (`description`, `hashedPassword`, `avatar`),
imported at the top of the host config. Each host overrides the machine-specific
parts — `defiant` uses `groups = ["wheel" "dialout"]` and no avatar, since it is
headless.

Per-entry options are `description`, `hashedPassword`, `shell` (defaults to
`pkgs.fish`), `groups`, and `avatar`. `wheel` is the admin group, so that list is
what decides whether a user can administer the machine.

`avatar` is wired to GDM through AccountsService rather than `~/.face`: the
module symlinks the icon into `/var/lib/AccountsService/icons/<user>` so it
updates on rebuild, and seeds the user's AccountsService config only if it does
not already exist, so the user can still change their avatar from Settings.

Home-manager attachment lives in `hosts/<machine>/default.nix`:

```nix
home-manager.users.thomasga.imports = [./home/thomasga.nix];
```

and the per-machine home module selects a profile and names the SSH identity
secret:

```nix
# hosts/<machine>/home/thomasga.nix
{
  imports = [../../../users/thomasga/desktop.nix];
  custom.ssh.identitySecret = "ssh-id-ed25519-enterprise-d";
}
```

### Assigning a user to one host or all hosts

- Declare the system account in a host-specific config if the user should exist
  only on that machine.
- Add a `hosts/<machine>/home/<user>.nix` and a `homeConfigurations` entry for
  each machine separately.
- Do not add a user to machines they do not use — groups, secrets, and
  home-manager builds are all per-machine.

## Add A New User

Two phases: a one-time system bootstrap requiring `wheel`, then ongoing
self-serve home-manager updates with no `sudo`.

### Phase 1 — System bootstrap (once, by a wheel user)

**1. Create the user's home-manager profile(s).** One per environment shape:

```text
users/alice/desktop.nix    # full GUI; imports ../common/base.nix, ../common/cli, etc.
users/alice/headless.nix   # CLI-only, for headless and WSL hosts
```

**2. Create per-machine home modules**, one file per machine the user will have
an account on:

```nix
# hosts/<machine>/home/alice.nix
{
  imports = [../../../users/alice/desktop.nix]; # or headless.nix
  custom.ssh.identitySecret = "ssh-id-ed25519-alice-<machine>";
}
```

**3. Declare the system account** in the relevant host config — groups are
machine-specific. Put the machine-independent attributes in
`users/alice/account.nix` and merge the per-machine ones on top, the way
`thomasga` does:

```nix
# hosts/<machine>/configuration.nix
custom.users.alice =
  alice
  // {
    groups = ["networkmanager"]; # wheel only if the user administers this machine
    avatar = null;
  };
```

**4. Attach home-manager** in `hosts/<machine>/default.nix`:

```nix
home-manager.users.alice.imports = [./home/alice.nix];
```

**5. Add `homeConfigurations` entries** in `flake.nix`, one per machine:

```nix
"alice@enterprise-d" = mkHomeConfig {
  user = "alice";
  machine = "enterprise-d";
  hostSystem = "x86_64-linux";
};
```

**6. Add an SSH identity secret** and declare it in `hosts/<machine>/secrets.nix`
— see [docs/secrets.md § SSH Keys And Host Trust](secrets.md#ssh-keys-and-host-trust).

**7. Apply:**

```bash
nix develop -c pre-commit run --all-files
sudo nixos-rebuild switch --flake .#<machine>
```

This is the only step requiring `sudo`. After it completes, the account exists
and the user can self-serve from here on.

### Phase 2 — Self-serve updates (no sudo)

Once the account exists, the user updates their own environment through the
`home-manager switch --flake .#<user>@<machine>` mechanism in
[docs/operations.md § User environment updates](operations.md#user-environment-updates-self-serve-no-sudo)
— no wheel user or system rebuild involved from here on.

## Dotfiles And Shell Scripts

Do not manually copy dotfiles after installation. Manage them through
home-manager and the shared `dotfiles` repo. Three patterns, in order of
preference.

### Pattern 1: shared look and feel via `dotfiles`

Fish aliases and functions, and git aliases and commit template, are no longer
rendered by home-manager. They live once in
[`geoff-coppertop/dotfiles`](https://github.com/geoff-coppertop/dotfiles), a
plain-file repo also consumed by `devcontainer-features`' `shell-baseline`
feature, so the same shell and git behavior appears on this machine and inside
devcontainers without being hand-copied in three places.

- `dotfiles` is pinned as a non-flake input
  (`inputs.dotfiles = { url = "github:geoff-coppertop/dotfiles"; flake = false; };`)
  in `flake.nix`, the same way every other input is pinned via `flake.lock`.
- `users/common/cli/dotfiles.nix` links `${dotfiles}/fish/config.fish`,
  `${dotfiles}/git/config`, and `${dotfiles}/git/commit-template` straight into
  place with plain `home.file.<path>.source` — no extra package, no activation
  step. home-manager's collision detection hard-errors at eval time if anything
  else tries to write those same paths.
- Because `programs.fish` stays disabled, and
  `programs.git`/`programs.fzf`/`programs.starship`/`programs.zoxide` must not
  also write `~/.config/fish/config.fish` or `~/.config/git/config`:
  `fzf.nix`/`starship.nix`/`zoxide.nix` set `enableFishIntegration = false` (the
  init lines already live in `dotfiles`' `config.fish`), `git.nix` drops
  `programs.git.enable` entirely and installs the `git` binary via
  `home.packages` instead, and `users/thomasga/git.nix` no longer sets
  `alias`/`color`/`commit.template` through `programs.git.settings`.
- Machine-specific git identity (`user.name`/`user.email`, `core.editor`,
  `safe.directory`, the `gh` credential-helper stanzas) is **not** published to
  the shared `dotfiles` repo. It stays home-manager-owned, written to
  `~/.config/git/config-local`, which `dotfiles`' `~/.config/git/config` pulls in
  via `[include] path = ~/.config/git/config-local`. Neither side clobbers the
  other's file.
- To change the shared shell and git look and feel, edit `dotfiles` directly and
  bump the pinned commit (`nix flake update dotfiles` here; bump the
  `dotfilesRef` default in `devcontainer-features`' `shell-baseline` separately).

### Pattern 2: use native home-manager options

For machine-specific or package-installation concerns a good native option
already covers:

```nix
programs.git = {
  enable = true;
  settings.user = {
    name = "Geoffrey Thomas";
    email = "you@example.com";
  };
};
```

### Pattern 3: keep a literal file in the repo

If you want to preserve an existing file mostly as-is and it is not shared with
devcontainers, create a per-user files directory such as `users/thomasga/files/`
and link it with `home.file`.

```nix
home.file.".gitconfig".source = ./files/gitconfig;
home.file.".local/bin/dev-shell".source = ./files/dev-shell;
```

## Home-Manager Idioms

**VS Code.** `programs.vscode` uses `profiles.default` for `extensions` and
`userSettings`. `argvSettings` (which maps to `argv.json`, e.g.
`disable-hardware-acceleration = true`) lives at the **top level**, not inside
the profile.

**Overriding app launch flags.** Use `xdg.desktopEntries.<name>` to replace a
package's `.desktop` file with a modified `exec` line — for example adding
`--disable-gpu`. Place it alongside the package declaration in `users/common/` or
`users/<name>/`.
