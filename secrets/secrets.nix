let
  enterprise-d = "age1nyd5azds343tn30m23x3ecmua9nfe04zhcrd7gq8qfp52kxk8a6snznw9l";

  holodeck-01 = "age1v6sv24jgrpdfex74d4d9xf92dpfy228lxmled4y4505py6ec7ghq4kmxz0";

  # Replace this with a distinct offline recovery key before expanding the fleet.
  offlineAdmin = "age135v2shcv64lul85dy5qqpwlnqw4rvdcsukymx63neqp37d9hpe0sp2jzp9";
in {
  "thomasga/restic-password.age".publicKeys = [enterprise-d offlineAdmin];
  "thomasga/nas-smb-credentials.age".publicKeys = [enterprise-d offlineAdmin];
  "thomasga/ssh-id-ed25519-enterprise-d.age".publicKeys = [enterprise-d offlineAdmin];
  "thomasga/github-token.age".publicKeys = [enterprise-d offlineAdmin];
  "wifi/agt-home.age".publicKeys = [enterprise-d offlineAdmin];
  "wifi/agt-iot.age".publicKeys = [enterprise-d offlineAdmin];
  "wifi/agt-work.age".publicKeys = [enterprise-d offlineAdmin];
  "thomasga/ssh-id-ed25519-holodeck-01.age".publicKeys = [holodeck-01 offlineAdmin];
}
