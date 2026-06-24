{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    # GitHub CLI — used directly and via git aliases (prc, prm, prs, prv)
    gh

    # Non-interactive replacement for Garmin's broken Connect IQ SDK Manager GUI
    (callPackage ../../pkgs/connect-iq-sdk-manager-cli.nix {})
  ];
}
