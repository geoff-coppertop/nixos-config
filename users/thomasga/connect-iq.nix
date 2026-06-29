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

  # Push the Garmin credentials (decrypted by agenix at boot, owned by
  # thomasga at /run/agenix/thomasga/garmin-*) into the systemd user
  # manager's environment so every child process inherits them:
  #   * desktop-launched apps (VS Code from .desktop) read them, so
  #     conectiq-bambu's devcontainer.json `${localEnv:GARMIN_*}`
  #     substitution resolves;
  #   * CLI-launched apps (terminal -> `code .`) also work, because the
  #     terminal emulator was itself spawned by systemd --user and
  #     inherits the env, then passes it down the shell.
  #
  # `systemctl --user import-environment` actively pushes values into the
  # user manager's env. We use this instead of the more common
  # `~/.config/environment.d/garmin.conf` file because that file is only
  # read by systemd --user at login -- a service that writes it later in
  # boot doesn't help the current session, and on first-ever login the
  # file doesn't exist yet.
  systemd.user.services.garmin-env = {
    Unit = {
      Description = "Import Garmin credentials into systemd --user environment";
      Before = ["graphical-session-pre.target"];
      PartOf = ["graphical-session-pre.target"];
    };
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "import-garmin-env" ''
        set -euo pipefail
        # `read -r` strips the trailing newline that any sane editor adds when
        # saving the secret via `nix run .#secret-edit`. Without this, the env
        # var would end in \n and Garmin login would silently fail.
        read -r GARMIN_USERNAME < /run/agenix/thomasga/garmin-username
        read -r GARMIN_PASSWORD < /run/agenix/thomasga/garmin-password
        export GARMIN_USERNAME GARMIN_PASSWORD
        ${pkgs.systemd}/bin/systemctl --user import-environment \
          GARMIN_USERNAME GARMIN_PASSWORD
      '';
    };
    Install.WantedBy = ["graphical-session-pre.target"];
  };
}
