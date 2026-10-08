{
  # Stock nixpkgs modules, no custom code. Radarr/Sonarr only index the
  # existing library (no download clients, no renaming -- tinyMediaManager
  # names files); Bazarr sits on top of them and writes subtitles next to
  # each video for Jellyfin. All three run as the media identity from
  # media.nix so they can write to the CIFS mount. Linking them and the
  # subtitle providers is done once in their UIs; see README § First-Time Service Setup.
  services = {
    radarr = {
      enable = true;
      user = "media";
      group = "media";
    };

    sonarr = {
      enable = true;
      user = "media";
      group = "media";
    };

    bazarr = {
      enable = true;
      user = "media";
      group = "media";
    };
  };

  # Same reliant-only restriction as Jellyfin and ARM in media.nix.
  networking.firewall.extraCommands = ''
    iptables -I nixos-fw -p tcp -s 192.168.20.15 --dport 7878 -j ACCEPT
    iptables -I nixos-fw -p tcp -s 192.168.20.15 --dport 8989 -j ACCEPT
    iptables -I nixos-fw -p tcp -s 192.168.20.15 --dport 6767 -j ACCEPT
  '';
}
