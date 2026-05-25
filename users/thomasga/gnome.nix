{
  config,
  lib,
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
  home = {
    file = {
      ".face".source = ./files/face.png;
      "Pictures/Wallpapers/space-shuttle.png".source = spaceShuttlePng;
      ".config/monitors.xml" = {
        force = true;
        text = ''
          <monitors version="2">
            <configuration>
              <logicalmonitor>
                <x>0</x>
                <y>0</y>
                <scale>2</scale>
                <primary>yes</primary>
                <monitor>
                  <monitorspec>
                    <connector>eDP-1</connector>
                    <vendor>BOE</vendor>
                    <product>NE135A1M-NY1</product>
                    <serial>0x00000000</serial>
                  </monitorspec>
                  <mode>
                    <width>2880</width>
                    <height>1920</height>
                    <rate>60.001</rate>
                  </mode>
                </monitor>
              </logicalmonitor>
            </configuration>
          </monitors>
        '';
      };
    };
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

    "org/gnome/desktop/peripherals/touchpad" = {
      natural-scroll = true;
    };

    "org/gnome/desktop/peripherals/mouse" = {
      natural-scroll = true;
    };

    "org/gnome/shell" = {
      enabled-extensions = [
        "battery-health-charging@alextrem.com"
        "blur-my-shell@aunetx"
        "dash-to-dock@micxgx.gmail.com"
        "just-perfection-desktop@just-perfection"
        "search-light@icedman.github.com"
      ];
      favorite-apps = [
        "org.gnome.Nautilus.desktop"
        "signal.desktop"
        "firefox.desktop"
        "code.desktop"
        "Alacritty.desktop"
        "steam.desktop"
        "com.moonlight_stream.Moonlight.desktop"
      ];
    };

    "org/gnome/shell/extensions/dash-to-dock" = {
      dock-fixed = false;
      autohide = true;
      intellihide = true;
    };

    "org/gnome/shell/extensions/search-light" = {
      shortcut-search = ["<Super>space"];
    };

    "org/gnome/desktop/session" = {
      idle-delay = lib.gvariant.mkUint32 240; # blank at 4 min, sleep at 5 min on battery
    };

    "org/gnome/desktop/screensaver" = {
      lock-enabled = true;
      lock-delay = lib.gvariant.mkUint32 0;
    };

    "org/gnome/settings-daemon/plugins/power" = {
      critical-battery-action = "hibernate";
      sleep-inactive-battery-timeout = 300; # 5 min idle on battery → suspend-then-hibernate
      sleep-inactive-battery-type = "suspend-then-hibernate";
      sleep-inactive-ac-timeout = 0; # on AC: only blank+lock, no sleep
    };

    # Free up Super+Space for search-light by clearing GNOME's input source switcher
    "org/gnome/settings-daemon/plugins/media-keys" = {
      switch-input-source = [];
      switch-input-source-backward = [];
    };
  };
}
