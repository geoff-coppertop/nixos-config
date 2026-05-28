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

  home.activation.ensureBuildsBookmark = lib.hm.dag.entryAfter ["writeBoundary"] ''
    bookmarksFile="$HOME/.config/gtk-3.0/bookmarks"
    mkdir -p "$(dirname "$bookmarksFile")"
    # Append only if absent so Nautilus can still manage other bookmarks freely
    if ! grep -qF "file://$HOME/builds" "$bookmarksFile" 2>/dev/null; then
      echo "file://$HOME/builds builds" >> "$bookmarksFile"
    fi
  '';

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

    # Single input source so the switcher popup never appears.
    # The <Super>space grab conflict is resolved by clearing wm.keybindings below.
    "org/gnome/desktop/input-sources" = {
      sources = [(lib.hm.gvariant.mkTuple ["xkb" "us"])];
    };

    "org/gnome/shell" = {
      enabled-extensions = [
        "blur-my-shell@aunetx"
        "dash-to-dock@micxgx.gmail.com"
        "just-perfection-desktop@just-perfection"
        "search-light@icedman.github.com"
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
        "com.bambulab.BambuStudio.desktop"
      ];
    };

    "org/gnome/shell/extensions/dash-to-dock" = {
      dock-fixed = false;
      autohide = true;
      # intellihide constantly re-checks window overlap, which races with
      # blur-my-shell's dock background actor on session init and creates an
      # infinite layout loop that hammers the GPU until XWayland dies.
      intellihide = false;
    };

    # Disable blur-my-shell's dock overlay — it adds MetaBackgroundGroup and
    # StWidget actors behind the dock that were the looping actors in the crash.
    "org/gnome/shell/extensions/blur-my-shell/dash-to-dock" = {
      blur = false;
    };

    # Writing shortcut-search triggers changed::shortcut-search, causing search-light
    # to re-grab. On first login the wm.keybindings default still holds <Super>space;
    # home-manager writes wm/keybindings before shell/extensions (alphabetical order),
    # releasing the conflict, then this key change fires the successful re-grab.
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
      # logind handles idle sleep on battery via IdleAction=suspend-then-hibernate.
      # gsd-power does not support suspend-then-hibernate as a sleep type and falls
      # back to plain Suspend(), which never transitions to hibernate. Set to nothing
      # so gsd-power does not race with logind's idle action.
      sleep-inactive-battery-type = "nothing";
      sleep-inactive-ac-timeout = 0; # on AC: only blank+lock, no sleep
    };

    # InputSourceManager reads switch-input-source from org.gnome.desktop.wm.keybindings
    # and registers it via Main.wm.addKeybinding — that is the Mutter-level grab that
    # blocks search-light. Clearing it here prevents the registration entirely.
    "org/gnome/desktop/wm/keybindings" = {
      switch-input-source = [];
      switch-input-source-backward = [];
    };

    # Belt-and-suspenders: also clear the legacy media-keys path and IBus trigger.
    "org/freedesktop/ibus/general/hotkey" = {
      triggers = [];
    };
    "org/gnome/settings-daemon/plugins/media-keys" = {
      switch-input-source = [];
      switch-input-source-backward = [];
    };

    "org/gnome/desktop/wm/preferences" = {
      button-layout = "appmenu:minimize,maximize,close";
    };

    "org/gnome/system/default-applications" = {
      web-browser = "firefox.desktop";
    };
  };

  # Bambu Studio ignores the XDG color-scheme portal; seed its own INI key.
  home.activation.bambuStudioDarkMode = lib.hm.dag.entryAfter ["writeBoundary"] ''
    _bbs_cfg="$HOME/.var/app/com.bambulab.BambuStudio/config/BambuStudio/BambuStudio.ini"
    if [ -f "$_bbs_cfg" ]; then
      if grep -q "^dark_color_scheme=" "$_bbs_cfg"; then
        sed -i 's/^dark_color_scheme=.*/dark_color_scheme=1/' "$_bbs_cfg"
      else
        echo "dark_color_scheme=1" >> "$_bbs_cfg"
      fi
    fi
  '';
}
