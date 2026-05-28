{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit
    (lib)
    filterAttrs
    mapAttrs
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.custom.networkDrives;
  enabledUsers = filterAttrs (_: u: u.enable) cfg.users;

  mkMountScript = username: userCfg:
    pkgs.writeShellScript "nas-drive-mount-${username}" ''
      set -euo pipefail

      creds="${userCfg.credentialsFile}"

      if [[ ! -f "$creds" ]]; then
        echo "nas-drive: credentials file not found, skipping" >&2
        exit 0
      fi

      smb_user=$(grep '^username=' "$creds" | cut -d= -f2-)
      smb_pass=$(grep '^password=' "$creds" | cut -d= -f2-)
      smb_uri="smb://${cfg.nas.host}/${userCfg.share}"

      existing=$(${pkgs.libsecret}/bin/secret-tool lookup \
        server "${cfg.nas.host}" \
        user "$smb_user" \
        protocol smb \
        share "${userCfg.share}" 2>/dev/null || true)

      if [[ "$existing" != "$smb_pass" ]]; then
        printf '%s' "$smb_pass" | ${pkgs.libsecret}/bin/secret-tool store \
          --label="NAS ($smb_user@${cfg.nas.host})" \
          xdg:schema org.gnome.keyring.NetworkPassword \
          server "${cfg.nas.host}" \
          user "$smb_user" \
          domain "${userCfg.workgroup}" \
          protocol smb \
          share "${userCfg.share}" 2>/dev/null || true
      fi

      if ! timeout 15 ${pkgs.glib}/bin/gio mount "$smb_uri" 2>/dev/null; then
        echo "nas-drive: NAS unreachable or mount timed out; skipping" >&2
        exit 0
      fi
    '';

  mkUnmountScript = username: userCfg:
    pkgs.writeShellScript "nas-drive-unmount-${username}" ''
      ${pkgs.glib}/bin/gio mount --unmount \
        "smb://${cfg.nas.host}/${userCfg.share}" 2>/dev/null || true
    '';

  mkUserHmConfig = username: userCfg: {
    systemd.user.services."nas-drive" = {
      Unit = {
        Description = "Mount NAS drive for ${username}";
        After = ["graphical-session.target"];
        PartOf = ["graphical-session.target"];
      };
      Service = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${mkMountScript username userCfg}";
        ExecStop = "${mkUnmountScript username userCfg}";
      };
      Install.WantedBy = ["graphical-session.target"];
    };
  };
in {
  options.custom.networkDrives = {
    enable = mkEnableOption "auto-mount SMB network drives at graphical login";

    nas.host = mkOption {
      type = types.str;
      description = "NAS hostname or IP address.";
    };

    users = mkOption {
      default = {};
      description = "Per-user SMB network drive configuration.";
      type = types.attrsOf (types.submodule ({name, ...}: {
        options = {
          enable = mkEnableOption "network drive for ${name}";

          share = mkOption {
            type = types.str;
            description = "SMB share name to mount (the share root, not a sub-path).";
          };

          credentialsFile = mkOption {
            type = types.str;
            default = "/run/agenix/${name}/nas-smb-credentials";
            description = "Path to the SMB credentials file (username=…/password=… format).";
          };

          workgroup = mkOption {
            type = types.str;
            default = "WORKGROUP";
            description = "SMB workgroup or domain.";
          };
        };
      }));
    };
  };

  config = mkIf cfg.enable {
    home-manager.users = mapAttrs (username: userCfg: mkUserHmConfig username userCfg) enabledUsers;
  };
}
