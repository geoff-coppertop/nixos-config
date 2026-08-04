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
    mapAttrs'
    mkEnableOption
    mkIf
    mkOption
    nameValuePair
    optional
    types
    ;

  cfg = config.custom.networkDrives;
  enabledUsers = filterAttrs (_: u: u.enable) cfg.users;

  # One declarative CIFS mount per enabled user. systemd automount keeps it
  # lazy and resilient: the share mounts on first access, never blocks boot or
  # the rebuild switch, and unmounts when idle. DE-independent and keyring-free
  # — no gio/GVfs, no gnome-keyring — mirroring roles/common/backups.nix, so it
  # works the same under GNOME, KDE, COSMIC, or a bare Wayland compositor.
  #
  # The default mountPoint is outside /home on purpose: an in-home mountpoint
  # would be pulled into the restic /home backup (custom.backups) and the whole
  # NAS share backed up to the NAS itself.
  mkMount = username: userCfg:
    nameValuePair userCfg.mountPoint {
      device = "//${cfg.nas.host}/${userCfg.share}";
      fsType = "cifs";
      options =
        [
          "credentials=${userCfg.credentialsFile}"
          "uid=${username}"
          "gid=${userCfg.group}"
          "forceuid"
          "forcegid"
          "file_mode=0700"
          "dir_mode=0700"
          "iocharset=utf8"
          "vers=3.0"
          "noauto"
          "nofail"
          "_netdev"
          "x-systemd.automount"
          "x-systemd.idle-timeout=10min"
          "x-systemd.mount-timeout=15s"
        ]
        ++ optional (userCfg.workgroup != null) "domain=${userCfg.workgroup}";
    };

  # Add the mountpoint to both the GTK bookmarks file (GTK file dialogs /
  # Nautilus) and Dolphin's Places sidebar, so the share appears in the file
  # manager regardless of the active desktop. Idempotent; each block only
  # touches its own entry and leaves the rest of the file to the file manager.
  #
  # No lib.hm.dag.entryAfter ["writeBoundary"] wrapper here: this value is
  # constructed by a NixOS (system-level) module, not a home-manager module, so
  # `lib` at this point is plain nixpkgs lib without home-manager's `.hm`
  # extension — `lib.hm` only exists inside home-manager's own module
  # evaluation. home-manager's dagOf type accepts a bare string as an
  # "anywhere" entry, which is fine here: the script only greps/appends to
  # files home-manager itself doesn't manage (GTK bookmarks, KDE places), so it
  # doesn't need to run strictly after home-manager's own file writes.
  mkBookmarkActivation = userCfg: ''
    gtkFile="$HOME/.config/gtk-3.0/bookmarks"
    ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$gtkFile")"
    if ! ${pkgs.gnugrep}/bin/grep -qF "file://${userCfg.mountPoint}" "$gtkFile" 2>/dev/null; then
      echo "file://${userCfg.mountPoint} ${userCfg.label}" >> "$gtkFile"
    fi

    placesFile="$HOME/.local/share/user-places.xbel"
    ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$placesFile")"
    if [ ! -e "$placesFile" ]; then
      ${pkgs.coreutils}/bin/printf '%s\n' \
        '<?xml version="1.0" encoding="UTF-8"?>' \
        '<!DOCTYPE xbel>' \
        '<xbel xmlns:bookmark="http://www.freedesktop.org/standards/desktop-bookmarks" xmlns:mime="http://www.freedesktop.org/standards/shared-mime-info" xmlns:kdepriv="http://www.kde.org/kdepriv">' \
        '</xbel>' > "$placesFile"
    fi
    if ! ${pkgs.gnugrep}/bin/grep -qF "file://${userCfg.mountPoint}" "$placesFile"; then
      bookmark=" <bookmark href=\"file://${userCfg.mountPoint}\"><title>${userCfg.label}</title><info><metadata owner=\"http://www.kde.org\"><isSystemItem>false</isSystemItem></metadata></info></bookmark>"
      ${pkgs.gnused}/bin/sed -i "s#</xbel>#$bookmark\n</xbel>#" "$placesFile"
    fi
  '';

  mkUserHmConfig = _username: userCfg: {
    home.activation.nasDriveBookmark = mkBookmarkActivation userCfg;
  };
in {
  options.custom.networkDrives = {
    enable = mkEnableOption "auto-mount SMB network drives via declarative CIFS";

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

          mountPoint = mkOption {
            type = types.str;
            default = "/mnt/nas/${name}";
            description = "Local mount point for the share. Kept outside /home so it is not swept into the restic home backup.";
          };

          label = mkOption {
            type = types.str;
            default = "NAS";
            description = "Sidebar label shown for the share in file managers.";
          };

          group = mkOption {
            type = types.str;
            default = "users";
            description = "Group that owns the mounted files (gid= for cifs).";
          };

          workgroup = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "SMB workgroup/domain. When null it is taken from the credentials file (or left unset).";
          };

          credentialsFile = mkOption {
            type = types.str;
            default = "/run/agenix/${name}/nas-smb-credentials";
            description = "Path to a mount.cifs credentials file (username=…/password=…[/domain=…]).";
          };
        };
      }));
    };
  };

  config = mkIf cfg.enable {
    # mount.cifs helper for the systemd .mount units.
    environment.systemPackages = [pkgs.cifs-utils];

    fileSystems = mapAttrs' mkMount enabledUsers;
    home-manager.users = mapAttrs mkUserHmConfig enabledUsers;
  };
}
