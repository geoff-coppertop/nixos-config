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

    # Bambu Studio ignores the XDG color-scheme portal; seed its own INI key.
    home.activation.bambuStudioColorScheme = lib.hm.dag.entryAfter ["writeBoundary"] ''
      _bbs_cfg="$HOME/.var/app/com.bambulab.BambuStudio/config/BambuStudio/BambuStudio.ini"
      if [ -f "$_bbs_cfg" ]; then
        if grep -q "^dark_color_scheme=" "$_bbs_cfg"; then
          sed -i 's/^dark_color_scheme=.*/dark_color_scheme=1/' "$_bbs_cfg"
        else
          echo "dark_color_scheme=1" >> "$_bbs_cfg"
        fi
      fi
    '';
  };
}
