{
  config,
  lib,
  osConfig ? null,
  ...
}: let
  # Read the DE choice from the NixOS layer (home-manager runs as a NixOS
  # module here, so osConfig is the system config). Falls back to "gnome" for
  # the standalone homeConfigurations, where osConfig is null — same pattern
  # as gnome.nix.
  de =
    if osConfig == null
    then "gnome"
    else osConfig.custom.desktop.environment or "gnome";
  wallpaper = "${config.home.homeDirectory}/Pictures/Wallpapers/space-shuttle.png";
in {
  config = lib.mkIf (de == "cosmic") {
    wayland.desktopManager.cosmic = {
      enable = true;

      # Dark mode is driven by the same custom.appearance.darkMode toggle that
      # feeds the GNOME dconf color-scheme in users/common/appearance.nix.
      appearance.theme.mode =
        if config.custom.appearance.darkMode
        then "dark"
        else "light";

      # All submodule fields are required by cosmic-manager (no defaults).
      wallpapers = [
        {
          output = "all";
          source = {
            __type = "enum";
            variant = "Path";
            value = [wallpaper];
          };
          filter_by_theme = false;
          filter_method = {
            __type = "enum";
            variant = "Lanczos";
          };
          sampling_method = {
            __type = "enum";
            variant = "Alphanumeric";
          };
          scaling_mode = {
            __type = "enum";
            variant = "Zoom";
          };
          # Single static wallpaper; rotation never fires but the field is required.
          rotation_frequency = 3600;
        }
      ];

      # DE-independence contract (profiles/desktop/power.nix): the DE owns screen
      # blanking only; logind owns all suspend decisions. The idle-hint user
      # service sets the logind IdleHint at 240s via ext-idle-notify-v1 (which
      # cosmic-comp implements), and IdleAction / the battery-idle-suspend
      # watchdog take it from there — same chain as GNOME.
      #
      # suspend_on_*_time = None is COSMIC's equivalent of the gsd-power
      # sleep-inactive-* off switches in gnome.nix: cosmic-idle must never
      # sleep the system or it would race logind.
      idle = {
        # Blank at 4 min, matching GNOME's idle-delay=240 so the suspend chain
        # (IdleHint at 240s, suspend ~270-300s) behaves identically on both DEs.
        screen_off_time = {
          __type = "optional";
          value = 240000;
        };
        suspend_on_ac_time = {
          __type = "optional";
          value = null;
        };
        suspend_on_battery_time = {
          __type = "optional";
          value = null;
        };
      };

      # Natural scrolling on both devices, matching gnome.nix's
      # org/gnome/desktop/peripherals/{touchpad,mouse}.natural-scroll = true.
      # scroll_config's own fields have no defaults (same "all submodule
      # fields required" caveat as wallpapers above), so method/scroll_button/
      # scroll_factor carry cosmic-manager's own documented values unchanged —
      # only natural_scroll actually differs from upstream's default (false).
      compositor = let
        scrollConfig = {
          method = {
            __type = "optional";
            value = {
              __type = "enum";
              variant = "Edge";
            };
          };
          natural_scroll = {
            __type = "optional";
            value = true;
          };
          scroll_button = {
            __type = "optional";
            value = 2;
          };
          scroll_factor = {
            __type = "optional";
            value = 1.0;
          };
        };
      in {
        input_default.scroll_config = {
          __type = "optional";
          value = scrollConfig;
        };
        input_touchpad.scroll_config = {
          __type = "optional";
          value = scrollConfig;
        };
      };

      # COSMIC's built-in default binds bare Super to the launcher and
      # Super+Space to input-source switching — the inverse of GNOME's setup,
      # where <Super>space opens search-light (gnome.nix) because a single
      # input source frees that combo up. Custom shortcuts are a separate
      # override layer on top of the built-in keymap (the same one COSMIC
      # Settings' own rebind UI writes to), so adding this doesn't remove the
      # bare-Super binding — it just gives Super+Space a second, expected way
      # to reach the launcher.
      shortcuts = [
        {
          key = "Super+Space";
          action = {
            __type = "enum";
            variant = "System";
            value = [
              {
                __type = "enum";
                variant = "Launcher";
              }
            ];
          };
        }
      ];

      # Dock favorites, equivalent to gnome.nix's org/gnome/shell.favorite-apps.
      # IDs are desktop-file basenames without the .desktop suffix; the file
      # manager becomes COSMIC's own (com.system76.CosmicFiles) since Nautilus
      # is GNOME-specific.
      applets."app-list".settings.favorites = [
        "firefox"
        "com.system76.CosmicFiles"
        "Mailspring"
        "signal"
        "code"
        "com.mitchellh.ghostty"
        "obsidian"
      ];
    };
  };
}
