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

  # Host-scoped (modules/desktop.nix); false for the standalone
  # homeConfigurations, same fallback rationale as `de` above.
  autohidePanel =
    if osConfig == null
    then false
    else osConfig.custom.desktop.autohidePanel or false;

  # The decoded PNG is produced and linked by users/thomasga/desktop-common.nix
  # (DE-neutral); point Plasma at that stable path rather than re-deriving it.
  wallpaper = "${config.home.homeDirectory}/Pictures/Wallpapers/space-shuttle.png";
in {
  config = lib.mkIf (de == "kde") {
    # Display scaling is deliberately NOT set here. Under Wayland, KWin stores
    # per-output scale in ~/.config/kwinoutputconfig.json keyed by a hardware
    # hash of the panel, so it can't be pinned portably in Nix. Set 200% once in
    # System Settings > Display & Monitor (matches the GNOME session's 2x
    # monitors.xml in users/thomasga/gnome.nix).

    # GNOME's natural-scroll = true is a device-CLASS default: it applies to
    # "any touchpad"/"any mouse" GNOME ever sees, with no hardware IDs
    # involved. KDE has no equivalent — kcminputrc only stores settings for
    # already-known devices, keyed by vendor/product/name
    # (plasma-manager's programs.plasma.input.touchpads/mice require those IDs
    # up front). To get GNOME's "just works for whatever's plugged in"
    # behaviour without hardcoding this laptop's specific hardware IDs, this
    # discovers every currently-connected mouse/touchpad at each activation
    # (via /proc/bus/input/devices — anything with a legacy "mouseN" evdev
    # handler, the kernel's own pointer-class marker) and writes
    # NaturalScroll=true for each via kwriteconfig6, KDE's own config-writing
    # tool, so the on-disk format is exactly what KDE itself produces.
    #
    # Coverage is at-activation, not hotplug: a device plugged in after the
    # last `nixos-rebuild switch`/login won't get this until the next one.
    # GNOME's schema-level default has no such gap. Re-run `home-manager
    # switch` (or just log out and back in) after connecting new hardware.
    home.activation.naturalScrollAllPointers = lib.hm.dag.entryAfter ["writeBoundary"] ''
      kwriteconfig6="${pkgs.kdePackages.kconfig}/bin/kwriteconfig6"
      ${pkgs.gawk}/bin/awk '
        BEGIN { RS = ""; FS = "\n" }
        {
          vendor = ""; product = ""; name = ""; ismouse = 0
          for (i = 1; i <= NF; i++) {
            if ($i ~ /^I: /) {
              if (match($i, /Vendor=[0-9a-fA-F]+/)) vendor = tolower(substr($i, RSTART + 7, RLENGTH - 7))
              if (match($i, /Product=[0-9a-fA-F]+/)) product = tolower(substr($i, RSTART + 8, RLENGTH - 8))
            }
            if ($i ~ /^N: Name=/) {
              name = $i
              sub(/^N: Name=/, "", name)
              gsub(/"/, "", name)
            }
            if ($i ~ /^H: Handlers=/ && $i ~ /mouse[0-9]/) ismouse = 1
          }
          if (ismouse && vendor != "" && product != "" && name != "") {
            print vendor "|" product "|" name
          }
        }
      ' /proc/bus/input/devices | while IFS='|' read -r vendor product name; do
        "$kwriteconfig6" --file kcminputrc \
          --group Libinput --group "$vendor" --group "$product" --group "$name" \
          --key NaturalScroll --type bool true
      done
    '';

    # Append ~/builds to Dolphin's Places sidebar (idempotent; only touches our
    # own entry so Dolphin stays free to manage the rest). The GTK bookmarks
    # equivalent for ~/builds is handled DE-neutrally in desktop-common.nix.
    home.activation.ensureBuildsPlace = lib.hm.dag.entryAfter ["writeBoundary"] ''
      placesFile="$HOME/.local/share/user-places.xbel"
      ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$placesFile")"
      if [ ! -e "$placesFile" ]; then
        ${pkgs.coreutils}/bin/printf '%s\n' \
          '<?xml version="1.0" encoding="UTF-8"?>' \
          '<!DOCTYPE xbel>' \
          '<xbel xmlns:bookmark="http://www.freedesktop.org/standards/desktop-bookmarks" xmlns:mime="http://www.freedesktop.org/standards/shared-mime-info" xmlns:kdepriv="http://www.kde.org/kdepriv">' \
          '</xbel>' > "$placesFile"
      fi
      href="file://$HOME/builds"
      if ! ${pkgs.gnugrep}/bin/grep -qF "$href" "$placesFile"; then
        bookmark=" <bookmark href=\"$href\"><title>builds</title><info><metadata owner=\"http://www.kde.org\"><isSystemItem>false</isSystemItem></metadata></info></bookmark>"
        ${pkgs.gnused}/bin/sed -i "s#</xbel>#$bookmark\n</xbel>#" "$placesFile"
      fi
    '';

    programs.plasma = {
      enable = true;

      workspace = {
        inherit wallpaper;
      };

      # plasma-manager's workspace module has no high-level accentColor option
      # (colorScheme only picks the scheme, not a custom accent within it), so
      # this goes through the generic configFile mechanism instead — the same
      # kdeglobals key System Settings' "Custom" accent-color picker writes.
      # #3daee9 (Breeze blue) as R,G,B, matching GNOME's accent-color = "blue".
      # AccentColorFromWallpaper is turned off so the explicit color always
      # wins instead of being overridden by wallpaper-derived accent.
      configFile."kdeglobals"."General" = {
        AccentColor = "61,174,233";
        AccentColorFromWallpaper = false;
      };

      # A single bottom panel that folds in the GNOME session's top bar (clock,
      # tray) and dash-to-dock-style pinned favourites. hiding is
      # host-controlled (custom.desktop.autohidePanel, modules/desktop.nix) —
      # dock-like autohide on small screens, always-visible otherwise.
      panels = [
        {
          location = "bottom";
          floating = true;
          height = 44;
          hiding =
            if autohidePanel
            then "autohide"
            else "none";
          widgets = [
            {
              name = "org.kde.plasma.kickoff";
              config.General.icon = "nix-snowflake-white";
            }
            {
              name = "org.kde.plasma.icontasks";
              config.General.launchers = [
                "applications:org.kde.dolphin.desktop"
                "applications:firefox.desktop"
                "applications:Mailspring.desktop"
                "applications:signal.desktop"
                "applications:code.desktop"
                "applications:com.mitchellh.ghostty.desktop"
                "applications:obsidian.desktop"
              ];
            }
            "org.kde.plasma.marginsseparator"
            "org.kde.plasma.systemtray"
            "org.kde.plasma.digitalclock"
          ];
        }
      ];

      kwin.titlebarButtons = {
        left = [];
        right = ["minimize" "maximize" "close"];
      };

      input.keyboard.layouts = [{layout = "us";}];

      # KRunner is the KDE equivalent of the GNOME session's search-light
      # spotlight; bind it to Super+Space (and keep Alt+Space). Spectacle
      # replaces GNOME's screenshot UI on Print and Super+Shift+S.
      shortcuts = {
        "org.kde.krunner.desktop"."_launch" = ["Meta+Space" "Alt+Space" "Search"];
        "org.kde.spectacle.desktop"."_launch" = ["Print" "Meta+Shift+S"];
      };

      kscreenlocker = {
        autoLock = true;
        lockOnResume = true;
        timeout = 4; # minutes; matches GNOME's 240s idle-delay
        appearance.wallpaper = wallpaper;
      };

      # Power policy is DE-independent here: logind owns idle suspend and lid
      # (hosts/enterprise-d/power.nix), UPower owns critical battery, and the
      # swayidle idle-hint unit in profiles/desktop/power.nix sets the logind
      # IdleHint at 240s on KWin. PowerDevil must therefore never suspend on its
      # own — it only dims/blanks the display, mirroring the GNOME session's
      # gsd-power off-switch in users/thomasga/gnome.nix.
      powerdevil = {
        AC = {
          autoSuspend.action = "nothing";
          turnOffDisplay.idleTimeout = 240;
          dimDisplay.enable = false;
        };
        battery = {
          autoSuspend.action = "nothing";
          turnOffDisplay.idleTimeout = 240;
          dimDisplay.enable = false;
        };
        lowBattery = {
          autoSuspend.action = "nothing";
        };
      };
    };
  };
}
