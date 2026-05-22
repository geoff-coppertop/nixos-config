let
  # The current checked-in secrets are scoped to the framework host.
  framework = "age1nyd5azds343tn30m23x3ecmua9nfe04zhcrd7gq8qfp52kxk8a6snznw9l";

  # Replace this with a distinct offline recovery key before expanding the fleet.
  offlineAdmin = "age135v2shcv64lul85dy5qqpwlnqw4rvdcsukymx63neqp37d9hpe0sp2jzp9";
in {
  "thomasga/restic-password.age".publicKeys = [framework offlineAdmin];
  "thomasga/nas-smb-credentials.age".publicKeys = [framework offlineAdmin];
  "thomasga/ssh-id-ed25519.age".publicKeys = [framework offlineAdmin];
  "wifi/agt-home.age".publicKeys = [framework offlineAdmin];
  "wifi/agt-iot.age".publicKeys = [framework offlineAdmin];
  "wifi/agt-work.age".publicKeys = [framework offlineAdmin];
}
