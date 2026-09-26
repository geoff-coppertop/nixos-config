{
  config,
  lib,
  ...
}: let
  cfg = config.custom.appearance;
in {
  options.custom.appearance.darkMode = lib.mkEnableOption "system-wide dark mode";

  config = lib.mkIf cfg.darkMode {
    dconf.settings."org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-application-prefer-dark-style = true;
    };

    # Bitwarden (Electron) doesn't reliably read the XDG color-scheme portal on Linux;
    # --force-dark-mode tells Chromium to report prefers-color-scheme:dark unconditionally.
    xdg.desktopEntries.bitwarden = {
      name = "Bitwarden";
      genericName = "Password Manager";
      exec = "env GTK_THEME=Adwaita:dark bitwarden --force-dark-mode %U";
      icon = "bitwarden";
      comment = "A secure and free password manager for all of your devices";
      categories = ["Utility"];
      mimeType = ["x-scheme-handler/bitwarden"];
      settings = {
        StartupWMClass = "Bitwarden";
        StartupNotify = "true";
      };
    };
  };
}
