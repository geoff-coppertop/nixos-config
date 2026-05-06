{
  services.snapper.configs = {
    root = {
      SUBVOLUME = "/";
      TIMELINE_CREATE = true;
      TIMELINE_CLEANUP = true;

      # Root is largely reproducible from the flake; local snapshots are mainly
      # useful for rolling back a bad rebuild or accidental /etc change within
      # the last few days. Note: btrfs snapshots are copy-on-write so an
      # unchanged snapshot costs negligible space, but snapper always creates
      # one on schedule regardless.
      TIMELINE_LIMIT_HOURLY = "5";
      TIMELINE_LIMIT_DAILY = "7";
      TIMELINE_LIMIT_WEEKLY = "2";
      TIMELINE_LIMIT_MONTHLY = "1";
      TIMELINE_LIMIT_YEARLY = "0";
    };

    home = {
      SUBVOLUME = "/home";
      TIMELINE_CREATE = true;
      TIMELINE_CLEANUP = true;

      # Home data is not reproducible, so keep a slightly longer window before
      # the NAS restic backups take over as the long-term record.
      TIMELINE_LIMIT_HOURLY = "5";
      TIMELINE_LIMIT_DAILY = "14";
      TIMELINE_LIMIT_WEEKLY = "4";
      TIMELINE_LIMIT_MONTHLY = "2";
      TIMELINE_LIMIT_YEARLY = "0";
    };
  };
}
