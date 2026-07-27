{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit
    (lib)
    concatLists
    filterAttrs
    mapAttrs
    mapAttrsToList
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

  config = {
    programs.fish.enable = true;

    users.users = mapAttrs mkUserConfig cfg;

    # GDM reads avatars from AccountsService, not ~/.face.
    # L+ symlinks the icon so it updates on rebuild.
    # C seeds the user config only if it doesn't already exist so AccountsService
    # can still write to it (e.g. if the user changes their avatar via Settings).
    systemd.tmpfiles.rules = tmpfileRules;
  };
}
