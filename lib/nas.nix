{
  ip = "192.168.1.21";
  host = "unas-pro";
  shares = rec {
    personal = "Personal-Drive";
    backups = "${personal}/backups";
  };
}
