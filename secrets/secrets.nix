let
  thomasga = "age1nyd5azds343tn30m23x3ecmua9nfe04zhcrd7gq8qfp52kxk8a6snznw9l";
in {
  "thomasga/restic-password.age".publicKeys = [thomasga];
  "thomasga/nas-smb-credentials.age".publicKeys = [thomasga];
}
