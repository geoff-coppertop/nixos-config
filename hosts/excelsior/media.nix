_: let
  nas = import ../../lib/nas.nix;

  # reliant's reserved LAN IP — the only host allowed to reach the ports
  # below. Matches this file's sibling restriction in configuration.nix for
  # the DCS control page and AdGuard admin UI.
  reliantIp = "192.168.20.15";

  # Shared identity for the media library, so a future ingestion tool (ARM,
  # tinyMediaManager) and Jellyfin can all reach the same CIFS mount without
  # clashing on ownership. Fixed numeric so the mount's uid/gid options are
  # stable.
  mediaUid = 5000;
  mediaGid = 5000;
in {
  users = {
    groups.media.gid = mediaGid;

    users.media = {
      isSystemUser = true;
      uid = mediaUid;
      group = "media";
      description = "Owns the Jellyfin media library mount";
    };

    # Lets Jellyfin read library files written by a future ingestion tool via
    # the shared group.
    users.jellyfin.extraGroups = ["media"];
  };

  # credentials= is the decrypted agenix secret, read by root at mount time.
  # Reuses the shared thomasga/nas-smb-credentials secret rather than minting a
  # per-host one — the media share is a subpath of the same Personal-Drive
  # share this host already mounts for backups (lib/nas.nix), so a separate
  # credential buys no isolation unless the NAS ACLs it independently. Same
  # path the custom.backups.nas block in configuration.nix uses.
  fileSystems."/mnt/media" = {
    device = "//${nas.host}/${nas.shares.media}";
    fsType = "cifs";
    options = [
      "nofail"
      "_netdev"
      "vers=3.0"
      "credentials=/run/agenix/thomasga/nas-smb-credentials"
      "uid=${toString mediaUid}"
      "gid=${toString mediaGid}"
      "file_mode=0664"
      "dir_mode=0775"
      "x-systemd.mount-timeout=15s"
    ];
  };

  # Order Jellyfin after the mount, but softly (wants, not requires) so a
  # temporarily unreachable NAS does not block it from starting.
  systemd.services.jellyfin = {
    after = ["mnt-media.mount"];
    wants = ["mnt-media.mount"];
  };

  custom.jellyfin = {
    enable = true;
    # No real auth of its own at the network layer beyond Jellyfin's own
    # accounts, and this host runs no Traefik — reliant's Traefik proxies it
    # cross-host (jellyfin.coppertop.ca), same pattern as this host's
    # existing dns2/DCS-control routes. openFirewall stays false; the
    # firewall rule below is the only thing that opens the port, and only to
    # reliant.
    openFirewall = false;
  };

  networking.firewall.extraCommands = ''
    iptables -I nixos-fw -p tcp -s ${reliantIp} --dport 8096 -j ACCEPT
  '';
}
