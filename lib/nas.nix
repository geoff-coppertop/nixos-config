{
  ip = "192.168.1.21";
  host = "unas-pro";
  # Three independent top-level shares on the NAS, each with its own NAS-side
  # account and ACL: `Personal-Drive` (the user's own login), `Backups`
  # (backup-svc), `Media` (media-svc). They are not subpaths of one another.
  shares = {
    personal = "Personal-Drive";
    backups = "Backups";
    media = "Media";

    # The pre-existing, years-old location of the thomasga home-directory
    # restic repository — a subpath of Personal-Drive, predating the
    # top-level Backups share entirely. custom.backups.users.thomasga (or
    # its per-entry override on hosts that also run backup-svc jobs) must
    # keep using this exact path, not the bare `personal` share above, or
    # it starts an unrelated, empty repository at a different remote
    # location and orphans the real history. Not to be confused with
    # `backups` above (the new, unrelated top-level Backups share used by
    # backup-svc for shared/appliance jobs).
    personalBackups = "Personal-Drive/backups";
  };
}
