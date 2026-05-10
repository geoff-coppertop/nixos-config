{
  config,
  pkgs,
  ...
}: let
  spaceShuttlePng =
    pkgs.runCommand "space-shuttle.png"
    {
      nativeBuildInputs = [pkgs.libjxl];
    }
    ''
      djxl ${./files/wallpapers/space-shuttle.jxl} "$out"
    '';
in {
  home.file."Pictures/Wallpapers/space-shuttle.png".source = spaceShuttlePng;

  # ULauncher hotkey configuration
  xdg.configFile."ulauncher/settings.json".text = builtins.toJSON {
    hotkey-show-app = "<Super>space";
    theme-name = "system";
    show-recent-apps = 3;
    grab-mouse-pointer = false;
  };

  dconf.settings = {
    "org/gnome/desktop/background" = {
      picture-uri = "file://${config.home.homeDirectory}/Pictures/Wallpapers/space-shuttle.png";
      picture-uri-dark = "file://${config.home.homeDirectory}/Pictures/Wallpapers/space-shuttle.png";
    };

    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-application-prefer-dark-style = true;
      accent-color = "blue";
    };

    "org/gnome/shell" = {
      enabled-extensions = [
        "battery-health-charging@alextrem.com"
        "blur-my-shell@aunetx"
        "dash-to-dock@micxgx.gmail.com"
        "just-perfection-desktop@just-perfection"
      ];
    };

    # Free up Super+Space for ULauncher by clearing GNOME's input source switcher
    "org/gnome/settings-daemon/plugins/media-keys" = {
      switch-input-source = [];
      switch-input-source-backward = [];
    };
  };
}
