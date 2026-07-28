{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit
    (lib)
    any
    attrValues
    concatLists
    filterAttrs
    mapAttrs
    mapAttrsToList
    mkIf
    mkOption
    optionals
    types
    ;
  sshHosts = import ../lib/ssh-hosts.nix;
  cfg = config.custom.users;

  authorizedKeysFor = userName:
    mapAttrsToList (_: host: host.userPublicKeys.${userName})
    (filterAttrs (_: host: host.userPublicKeys ? ${userName}) sshHosts);

  mkUserConfig = userName: userCfg: {
    isNormalUser = true;
    inherit (userCfg) description hashedPassword shell;
    extraGroups = userCfg.groups;
    openssh.authorizedKeys.keys = authorizedKeysFor userName;
  };

  accountsServiceFile = userName:
    pkgs.writeText "${userName}-accountsservice"
    "[User]\nIcon=/var/lib/AccountsService/icons/${userName}\nSystemAccount=false\n";

  mkTmpfileRules = userName: userCfg:
    optionals (userCfg.avatar != null) [
      "L+ /var/lib/AccountsService/icons/${userName} - - - - ${toString userCfg.avatar}"
      "C /var/lib/AccountsService/users/${userName} 0644 root root - ${accountsServiceFile userName}"
    ];

  tmpfileRules = concatLists (mapAttrsToList mkTmpfileRules cfg);

  # users.users.<name>.shell = pkgs.fish requires programs.fish.enable, which
  # is what puts fish in /etc/shells — without it the login shell is invalid.
  # Derive it from the declared users rather than hardcoding, so a host that
  # declares only non-fish users doesn't get fish.
  usesShell = shell: any (userCfg: userCfg.shell == shell) (attrValues cfg);
in {
  options.custom.users = mkOption {
    default = {};
    description = "System user accounts to create on this host.";
    type = types.attrsOf (types.submodule ({name, ...}: {
      options = {
        description = mkOption {
          type = types.str;
          default = name;
        };
        hashedPassword = mkOption {
          type = types.str;
        };
        shell = mkOption {
          type = types.package;
          default = pkgs.fish;
        };
        groups = mkOption {
          type = types.listOf types.str;
          default = [];
        };
        avatar = mkOption {
          type = types.nullOr types.path;
          default = null;
        };
      };
    }));
  };

  config = mkIf (cfg != {}) {
    # mkIf rather than a plain bool: types.bool merges with mergeEqualOption,
    # so defining `false` here would conflict with anything else asking for
    # fish. With mkIf, a host whose users all use another shell gets no
    # definition at all.
    programs.fish.enable = mkIf (usesShell pkgs.fish) true;

    users.users = mapAttrs mkUserConfig cfg;

    # GDM reads avatars from AccountsService, not ~/.face.
    # L+ symlinks the icon so it updates on rebuild.
    # C seeds the user config only if it doesn't already exist so AccountsService
    # can still write to it (e.g. if the user changes their avatar via Settings).
    systemd.tmpfiles.rules = tmpfileRules;
  };
}
