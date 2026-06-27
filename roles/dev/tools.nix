{pkgs, ...}: {
  # Garmin's ConnectIQ SDK ships monkeyc with a #!/bin/bash shebang, which
  # doesn't exist on NixOS by default.
  custom.binCompat.enable = true;

  environment.systemPackages = with pkgs; [
    # GitHub CLI — used directly and via git aliases (prc, prm, prs, prv)
    gh

    # Non-interactive replacement for Garmin's broken Connect IQ SDK Manager GUI
    (callPackage ../../pkgs/connect-iq-sdk-manager-cli.nix {})

    # monkeyc (ConnectIQ SDK) is a Java app and needs a JRE on PATH
    jdk
  ];
}
