{
  lib,
  pkgs,
  ...
}: {
  # Replicates the manual first-run steps (mkdir + agreement accept) so a
  # fresh machine doesn't need them done interactively before `sdk download`
  # works.
  home.activation.acceptConnectIqAgreement = lib.hm.dag.entryAfter ["writeBoundary"] ''
    marker="$HOME/.local/state/connect-iq-agreement-accepted"
    if [ ! -f "$marker" ]; then
      $DRY_RUN_CMD mkdir -p "$HOME/.Garmin/ConnectIQ/Sdks"
      run ${pkgs.callPackage ../../pkgs/connect-iq-sdk-manager-cli.nix {}}/bin/connect-iq-sdk-manager agreement accept
      $DRY_RUN_CMD mkdir -p "$HOME/.local/state"
      $DRY_RUN_CMD touch "$marker"
    fi
  '';
}
