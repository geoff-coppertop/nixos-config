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
      gtk-theme = "gnome-prism";
      icon-theme = "gnome-prism";
    };

    "org/gnome/desktop/peripherals/touchpad" = {
      natural-scroll = true;
    };

    "org/gnome/desktop/peripherals/mouse" = {
      natural-scroll = true;
    };

    # Single input source prevents InputSourceManager from registering <Super>space
    "org/gnome/desktop/input-sources" = {
      sources = [(lib.hm.gvariant.mkTuple ["xkb" "us"])];
    };

    "org/gnome/shell" = {
      enabled-extensions = [
        "blur-my-shell@aunetx"
        "dash-to-panel@jderose9.github.com"
        "just-perfection-desktop@just-perfection"
        "search-light@icedman.github.com"
        "user-theme@gnome-shell-extensions.gcampax.github.com"
      ];
      favorite-apps = [
        "org.gnome.Nautilus.desktop"
        "obsidian.desktop"
        "signal.desktop"
        "firefox.desktop"
        "code.desktop"
        "com.mitchellh.ghostty.desktop"
        "steam.desktop"
        "com.moonlight_stream.Moonlight.desktop"
      ];
    };

    "org/gnome/shell/extensions/user-theme" = {
      name = "gnome-prism";
    };

    "org/gnome/shell/extensions/dash-to-panel" = {
      panel-positions = ''{"0":"BOTTOM"}'';
      autohide-panel = true;
      stockgs-keep-top-panel = false;
      panel-element-positions-monitors-sync = true;
      panel-element-positions = ''{"0":[{"element":"showAppsButton","visible":true,"position":"stackedTL"},{"element":"activitiesButton","visible":false,"position":"stackedTL"},{"element":"leftBox","visible":true,"position":"stackedTL"},{"element":"taskbar","visible":true,"position":"stackedTL"},{"element":"centerBox","visible":false,"position":"stackedBR"},{"element":"rightBox","visible":true,"position":"stackedBR"},{"element":"systemMenu","visible":true,"position":"stackedBR"},{"element":"dateMenu","visible":true,"position":"stackedBR"},{"element":"desktopButton","visible":false,"position":"stackedBR"}]}'';
      panel-lengths = ''{"0":100}'';
      panel-anchors = ''{"0":"MIDDLE"}'';
      panel-size = 55;
      appicon-padding = 10;
      appicon-margin = 0;
      tray-padding = 0;
      leftbox-padding = 0;
      status-icon-padding = 0;
      show-apps-icon-side-padding = 12;
      tray-size = 14;
      leftbox-size = 14;
      trans-use-custom-bg = true;
      trans-bg-color = "#000000";
      trans-use-border = true;
      trans-border-width = 1;
      trans-border-use-custom-color = true;
      trans-border-custom-color = "#89B4FA";
      dot-style-focused = "SQUARES";
      dot-style-unfocused = "SQUARES";
      dot-position = "BOTTOM";
      dot-size = 0;
      focus-highlight = false;
      group-apps-underline-unfocused = false;
      animate-appicon-hover = true;
      highlight-appicon-hover = false;
      animate-appicon-hover-animation-type = "SIMPLE";
    };

    # Writing shortcut-search via dconf triggers changed::shortcut-search in the
    # running session, which causes the extension to re-grab the accelerator. This
    # post-startup re-grab (with the parseInt fix in place) resolves any grab
    # conflict that may have occurred during initial session setup.
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

    # Free up Super+Space for search-light — clear GNOME media keys and IBus grab
    "org/freedesktop/ibus/general/hotkey" = {
      triggers = [];
    };

    "org/gnome/desktop/wm/preferences" = {
      button-layout = "appmenu:minimize,maximize,close";
    };

    "org/gnome/system/default-applications" = {
      web-browser = "firefox.desktop";
    };
    "org/gnome/settings-daemon/plugins/media-keys" = {
      switch-input-source = [];
      switch-input-source-backward = [];
    };
  };
}
