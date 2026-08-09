let
  localFile = import ../../lib/local-file.nix;
in {
  description = "Geoffrey Thomas";
  hashedPassword = "$6$wDwCuj.CXA58mdJ4$IxPk211Ubqn8ZZp7pezRajIaQye6dp47gMVd4xpnmiCmml8MfSqDiR3SU8FXn1r/urLDEsNz/oOM3GTGHiitD.";
  avatar = localFile {path = ./files/face.png;};
}
