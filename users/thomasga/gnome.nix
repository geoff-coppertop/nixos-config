{
  config,
  lib,
  osConfig ? null,
  pkgs,
  ...
}: let
  # Read the DE choice from the NixOS layer (home-manager runs as a NixOS
  # module here, so osConfig is the system config). Falls back to "gnome" for
  # the standalone homeConfigurations, where osConfig is null.
  de =
    if osConfig == null
    then "gnome"
    else osConfig.custom.desktop.environment or "gnome";
in {
  config = lib.mkIf (de == "gnome") {
    home = {
      file.".config/monitors.xml" = {
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

      activation = {
        # Reset the app-folders dconf subtree before home-manager writes the
        # new folder definitions so stale entries don't confuse gnome-shell.
        resetAppFolders = lib.hm.dag.entryBefore ["dconfSettings"] ''
          if [ -n "''${DBUS_SESSION_BUS_ADDRESS:-}" ] || [ -S "/run/user/$(id -u)/bus" ]; then
            ${pkgs.dconf}/bin/dconf reset -f /org/gnome/desktop/app-folders/ || true
          fi
        '';

        # Pin every folder to page 1. Without this, gnome-shell's saved
        # app-picker-layout pushes folders onto page 2 or off the visible pages.
        pinAppFoldersToPageOne = lib.hm.dag.entryAfter ["dconfSettings"] ''
          if [ -n "''${DBUS_SESSION_BUS_ADDRESS:-}" ] || [ -S "/run/user/$(id -u)/bus" ]; then
            ${pkgs.dconf}/bin/dconf write /org/gnome/shell/app-picker-layout "[{ \
              'Engineering': <{'position': <0>}>, \
              'Games':       <{'position': <1>}>, \
              'Media':       <{'position': <2>}>, \
              'System':      <{'position': <3>}> \
            }]" || true
          fi
        '';
      };
    };

    # GNOME-only launcher noise (these apps ship as GNOME deps). Generic
    # noDisplay entries live in desktop-common.nix.
    xdg.desktopEntries = {
      # Rygel is a background DLNA/UPnP service — not user-launchable.
      rygel = {
        name = "Rygel";
        noDisplay = true;
      };
      rygel-preferences = {
        name = "Rygel Preferences";
        noDisplay = true;
      };
      # Diagnostic tool for ICC profiles, not a user-launchable app.
      "org.gnome.ColorProfileViewer" = {
        name = "Color Profile Viewer";
        noDisplay = true;
      };
    };

    dconf.settings = {
      "org/gnome/desktop/background" = {
        picture-uri = "file://${config.home.homeDirectory}/Pictures/Wallpapers/space-shuttle.png";
        picture-uri-dark = "file://${config.home.homeDirectory}/Pictures/Wallpapers/space-shuttle.png";
      };

      "org/gnome/desktop/interface" = {
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
        # Trimmed to daily-use apps. Engineering/Games/Media/System apps live
        # in app-pane folders; reach them via Activities or <Super>Space.
        favorite-apps = [
          "org.gnome.Nautilus.desktop"
          "firefox.desktop"
          "Mailspring.desktop"
          "signal.desktop"
          "code.desktop"
          "com.mitchellh.ghostty.desktop"
          "obsidian.desktop"
        ];
      };

      # App-pane folders. GNOME 46+ excludes favorite-apps (dock) from the app
      # grid, so folders only cover apps not pinned to the dock.
      "org/gnome/desktop/app-folders" = {
        folder-children = [
          "Engineering"
          "Games"
          "Media"
          "System"
        ];
      };
      # translate=false: prevents gnome-shell treating the name as a translation
      # key, which causes collisions with built-in category directories.
      "org/gnome/desktop/app-folders/folders/Engineering" = {
        name = "Engineering";
        translate = false;
        apps = ["onshape.desktop" "com.bambulab.BambuStudio.desktop" "qgroundcontrol.desktop" "companion211.desktop" "simulator211.desktop"];
      };
      "org/gnome/desktop/app-folders/folders/Games" = {
        name = "Games";
        translate = false;
        apps = ["steam.desktop" "com.moonlight_stream.Moonlight.desktop" "alvr.desktop"];
        categories = ["Game"];
      };
      "org/gnome/desktop/app-folders/folders/Media" = {
        name = "Media";
        translate = false;
        apps = [
          "org.gnome.Loupe.desktop"
          "org.gnome.Showtime.desktop"
          "org.gnome.Snapshot.desktop"
        ];
      };
      "org/gnome/desktop/app-folders/folders/System" = {
        name = "System";
        translate = false;
        apps = [
          "org.gnome.Nautilus.desktop"
          "org.gnome.Settings.desktop"
          "org.gnome.DiskUtility.desktop"
          "org.gnome.SystemMonitor.desktop"
          "org.gnome.Software.desktop"
          "org.gnome.tweaks.desktop"
          "org.gnome.Extensions.desktop"
          "cups.desktop"
          "com.github.tchx84.Flatseal.desktop"
          "framework-control.desktop"
          "bitwarden.desktop"
          "org.fedoraproject.MediaWriter.desktop"
          "org.gnome.seahorse.Application.desktop"
          "org.gnome.Papers.desktop"
          "btop.desktop"
        ];
      };

      "org/gnome/shell/extensions/dash-to-dock" = {
        dock-fixed = false;
        autohide = true;
        # intellihide races with blur-my-shell's dock background actor on session
        # init, creating an infinite layout loop that hammers the GPU until XWayland dies.
        intellihide = false;
      };

      # Disable blur-my-shell's dock overlay — the looping actors in the crash.
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
        # Blank at 4 min. Also the moment Mutter sets the logind session
        # IdleHint=yes — the trigger the DE-independent suspend chain keys on
        # (see the idle-hint contract in roles/desktop/power.nix). Keep in sync
        # with the 240s swayidle timeout there.
        idle-delay = lib.gvariant.mkUint32 240;
      };

      "org/gnome/desktop/screensaver" = {
        lock-enabled = true;
        lock-delay = lib.gvariant.mkUint32 0;
      };

      # Power policy is DE-independent: logind owns idle suspend and lid
      # (hosts/enterprise-d/power.nix), UPower owns critical battery
      # (roles/desktop/power.nix). These keys are the GNOME-side off switch so
      # gsd-power never competes with that — it also respects application
      # suspend inhibitors (e.g. Firefox "Playing video"), so it could not be
      # trusted to sleep on battery anyway; the battery-idle-suspend watchdog
      # forces `suspend -i` past 300s idle instead.
      "org/gnome/settings-daemon/plugins/power" = {
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

      "org/gnome/shell/keybindings" = {
        show-screenshot-ui = ["Print" "<Super><Shift>s"];
      };

      "org/gnome/desktop/wm/preferences" = {
        button-layout = "appmenu:minimize,maximize,close";
      };

      "org/gnome/system/default-applications" = {
        web-browser = "firefox.desktop";
      };
    };
  };
}
