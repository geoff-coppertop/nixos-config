{
  ip = "192.168.1.21";
  host = "unas-pro";
  shares = rec {
    personal = "Personal-Drive";
    backups = "${personal}/backups";
    # Jellyfin media library. Adjust to match the actual share/path on the NAS.
    media = "${personal}/media";
  };
}
