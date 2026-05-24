{pkgs, ...}: {
  users.users.thomasga = {
    isNormalUser = true;
    description = "Geoffrey Thomas";
    extraGroups = ["wheel" "networkmanager"];
    hashedPassword = "$6$wDwCuj.CXA58mdJ4$IxPk211Ubqn8ZZp7pezRajIaQye6dp47gMVd4xpnmiCmml8MfSqDiR3SU8FXn1r/urLDEsNz/oOM3GTGHiitD.";
  };

  # GDM reads avatars from AccountsService, not ~/.face.
  # L+ symlinks the icon so it updates on rebuild.
  # C seeds the user config only if it doesn't already exist so AccountsService
  # can still write to it (e.g. if the user changes their avatar via Settings).
  systemd.tmpfiles.rules = [
    "L+ /var/lib/AccountsService/icons/thomasga - - - - ${../../users/thomasga/files/face.png}"
    "C /var/lib/AccountsService/users/thomasga 0644 root root - ${pkgs.writeText "thomasga-accountsservice" ''
      [User]
      Icon=/var/lib/AccountsService/icons/thomasga
      SystemAccount=false
    ''}"
  ];
}
