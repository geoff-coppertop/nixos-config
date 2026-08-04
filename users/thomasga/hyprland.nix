{
  config,
  lib,
  osConfig ? null,
  pkgs,
  ...
}: let
  de =
    if osConfig == null
    then "gnome"
    else osConfig.custom.desktop.environment or "gnome";

  wallpaper = "${config.home.homeDirectory}/Pictures/Wallpapers/space-shuttle.png";
  screenshotDir = "${config.home.homeDirectory}/Pictures/Screenshots";

  # grim+slurp screenshots that both save a file and copy to the clipboard,
  # matching GNOME's Print / <Super><Shift>S behaviour.
  screenshotFull = pkgs.writeShellScript "screenshot-full" ''
    ${pkgs.coreutils}/bin/mkdir -p "${screenshotDir}"
    file="${screenshotDir}/$(${pkgs.coreutils}/bin/date +%Y-%m-%d_%H-%M-%S).png"
    ${pkgs.grim}/bin/grim "$file"
    ${pkgs.wl-clipboard}/bin/wl-copy < "$file"
    ${pkgs.libnotify}/bin/notify-send "Screenshot saved" "$file"
  '';

  screenshotRegion = pkgs.writeShellScript "screenshot-region" ''
    ${pkgs.coreutils}/bin/mkdir -p "${screenshotDir}"
    file="${screenshotDir}/$(${pkgs.coreutils}/bin/date +%Y-%m-%d_%H-%M-%S).png"
    ${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp)" "$file" || exit 0
    ${pkgs.wl-clipboard}/bin/wl-copy < "$file"
    ${pkgs.libnotify}/bin/notify-send "Screenshot saved" "$file"
  '';

  # wofi-backed clipboard-history picker over cliphist's store.
  clipboardHistory = pkgs.writeShellScript "clipboard-history" ''
    ${pkgs.cliphist}/bin/cliphist list \
      | ${pkgs.wofi}/bin/wofi --dmenu --prompt "Clipboard" \
      | ${pkgs.cliphist}/bin/cliphist decode \
      | ${pkgs.wl-clipboard}/bin/wl-copy
  '';
in {
  config = lib.mkIf (de == "hyprland") {
    home = {
      packages = with pkgs; [
        grim
        slurp
        wl-clipboard
        brightnessctl
        playerctl
        pavucontrol
        libnotify
        nautilus # file manager (Super+E); brings gvfs for trash/mounts
        networkmanagerapplet # nm-connection-editor, launched from the Waybar network module
      ];

      pointerCursor = {
        name = "Adwaita";
        package = pkgs.adwaita-icon-theme;
        size = 24;
        gtk.enable = true;
      };
    };

    wayland.windowManager.hyprland = {
      enable = true;
      # systemd.enable (default true) pulls the session env into the user
      # systemd/dbus environment and starts graphical-session.target, which is
      # what the waybar/mako/hypridle/hyprpaper/cliphist services below bind to.
      settings = {
        # Framework 13 panel: match the GNOME scale=2 HiDPI setup (logical
        # 1440x960). Replaces users/thomasga monitors.xml under this session.
        monitor = ["eDP-1,2880x1920@60,0x0,2"];

        "$mod" = "SUPER";
        "$terminal" = "ghostty";
        "$menu" = "${pkgs.wofi}/bin/wofi --show drun";
        "$fileManager" = "${pkgs.nautilus}/bin/nautilus";

        env = [
          "XCURSOR_SIZE,24"
          "HYPRCURSOR_SIZE,24"
        ];

        general = {
          gaps_in = 5;
          gaps_out = 10;
          border_size = 2;
          "col.active_border" = "rgba(3584e4ee) rgba(62a0eaee) 45deg";
          "col.inactive_border" = "rgba(31313100)";
          layout = "dwindle";
        };

        decoration = {
          rounding = 8;
          blur = {
            enabled = true;
            size = 6;
            passes = 2;
          };
        };

        input = {
          kb_layout = "us";
          follow_mouse = 1;
          # Match GNOME's natural-scroll = true for touchpad and mouse.
          natural_scroll = true;
          touchpad = {
            natural_scroll = true;
            tap-to-click = true;
          };
        };

        gestures.workspace_swipe = true;

        misc = {
          disable_hyprland_logo = true;
          disable_splash_rendering = true;
        };

        bind = [
          "$mod, RETURN, exec, $terminal"
          "$mod, SPACE, exec, $menu" # launcher on Super+Space, matching search-light
          "$mod, Q, killactive"
          "$mod, E, exec, $fileManager"
          "$mod, F, fullscreen"
          "$mod, V, togglefloating"
          "$mod, L, exec, ${pkgs.systemd}/bin/loginctl lock-session"
          "$mod SHIFT, V, exec, ${clipboardHistory}"

          ", Print, exec, ${screenshotFull}"
          "$mod SHIFT, S, exec, ${screenshotRegion}"

          "$mod, left, movefocus, l"
          "$mod, right, movefocus, r"
          "$mod, up, movefocus, u"
          "$mod, down, movefocus, d"

          "$mod, 1, workspace, 1"
          "$mod, 2, workspace, 2"
          "$mod, 3, workspace, 3"
          "$mod, 4, workspace, 4"
          "$mod, 5, workspace, 5"
          "$mod, 6, workspace, 6"
          "$mod, 7, workspace, 7"
          "$mod, 8, workspace, 8"
          "$mod, 9, workspace, 9"
          "$mod, 0, workspace, 10"

          "$mod SHIFT, 1, movetoworkspace, 1"
          "$mod SHIFT, 2, movetoworkspace, 2"
          "$mod SHIFT, 3, movetoworkspace, 3"
          "$mod SHIFT, 4, movetoworkspace, 4"
          "$mod SHIFT, 5, movetoworkspace, 5"
          "$mod SHIFT, 6, movetoworkspace, 6"
          "$mod SHIFT, 7, movetoworkspace, 7"
          "$mod SHIFT, 8, movetoworkspace, 8"
          "$mod SHIFT, 9, movetoworkspace, 9"
          "$mod SHIFT, 0, movetoworkspace, 10"
        ];

        # binde = repeat while held (volume/brightness ramps).
        binde = [
          ", XF86AudioRaiseVolume, exec, ${pkgs.wireplumber}/bin/wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"
          ", XF86AudioLowerVolume, exec, ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
          ", XF86MonBrightnessUp, exec, ${pkgs.brightnessctl}/bin/brightnessctl set 5%+"
          ", XF86MonBrightnessDown, exec, ${pkgs.brightnessctl}/bin/brightnessctl set 5%-"
        ];

        # bindl = fire even when the session is locked.
        bindl = [
          ", XF86AudioMute, exec, ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
          ", XF86AudioMicMute, exec, ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
          ", XF86AudioPlay, exec, ${pkgs.playerctl}/bin/playerctl play-pause"
          ", XF86AudioNext, exec, ${pkgs.playerctl}/bin/playerctl next"
          ", XF86AudioPrev, exec, ${pkgs.playerctl}/bin/playerctl previous"
        ];

        bindm = [
          "$mod, mouse:272, movewindow"
          "$mod, mouse:273, resizewindow"
        ];

        windowrulev2 = [
          "float, class:^(pavucontrol)$"
          "float, class:^(nm-connection-editor)$"
          "float, title:^(Picture-in-Picture)$"
        ];
      };
    };

    programs = {
      # ── Bar ────────────────────────────────────────────────────────────────
      waybar = {
        enable = true;
        systemd.enable = true;
        settings.mainBar = {
          layer = "top";
          position = "top";
          height = 30;
          modules-left = ["hyprland/workspaces"];
          modules-center = ["clock"];
          modules-right = ["tray" "pulseaudio" "network" "backlight" "battery"];

          clock = {
            format = "{:%a %d %b  %H:%M}";
            tooltip-format = "<tt>{calendar}</tt>";
          };
          pulseaudio = {
            format = "{volume}% {icon}";
            format-muted = "muted ";
            format-icons.default = ["" "" ""];
            on-click = "${pkgs.pavucontrol}/bin/pavucontrol";
          };
          network = {
            format-wifi = "{essid} ";
            format-ethernet = "wired ";
            format-disconnected = "offline ";
            tooltip-format = "{ipaddr}";
            on-click = "${pkgs.networkmanagerapplet}/bin/nm-connection-editor";
          };
          backlight = {
            format = "{percent}% {icon}";
            format-icons = ["" ""];
          };
          battery = {
            format = "{capacity}% {icon}";
            format-charging = "{capacity}% ";
            format-icons = ["" "" "" "" ""];
            states = {
              warning = 20;
              critical = 10;
            };
          };
          tray.spacing = 8;
        };
        style = ''
          * {
            font-family: "DroidSansM Nerd Font", monospace;
            font-size: 13px;
          }
          window#waybar {
            background: #1e1e2e;
            color: #ffffff;
          }
          #workspaces button {
            padding: 0 8px;
            color: #cdd6f4;
            background: transparent;
          }
          #workspaces button.active {
            color: #ffffff;
            background: #3584e4;
          }
          #clock,
          #pulseaudio,
          #network,
          #backlight,
          #battery,
          #tray {
            padding: 0 10px;
          }
          #battery.warning {
            color: #f9e2af;
          }
          #battery.critical {
            color: #f38ba8;
          }
        '';
      };

      # ── Launcher ───────────────────────────────────────────────────────────
      wofi = {
        enable = true;
        settings = {
          show = "drun";
          prompt = "Search";
          width = 600;
          height = 400;
          allow_images = true;
          insensitive = true;
        };
        style = ''
          window {
            background-color: #1e1e2e;
            color: #ffffff;
            border-radius: 8px;
          }
          #input {
            margin: 8px;
            padding: 8px;
            border-radius: 6px;
            background-color: #313244;
            color: #ffffff;
          }
          #entry:selected {
            background-color: #3584e4;
          }
        '';
      };

      # ── Screen lock ────────────────────────────────────────────────────────
      hyprlock = {
        enable = true;
        settings = {
          background = [
            {
              path = wallpaper;
              blur_passes = 2;
              blur_size = 6;
            }
          ];
          input-field = [
            {
              size = "250, 50";
              position = "0, -80";
              outline_thickness = 2;
              dots_center = true;
              fade_on_empty = false;
              placeholder_text = "<i>Password or fingerprint…</i>";
            }
          ];
          label = [
            {
              text = "$TIME";
              font_size = 64;
              position = "0, 120";
              halign = "center";
              valign = "center";
            }
          ];
        };
      };
    };

    services = {
      # ── Notifications ──────────────────────────────────────────────────────
      mako = {
        enable = true;
        settings = {
          background-color = "#1e1e2e";
          text-color = "#ffffff";
          border-color = "#3584e4";
          border-radius = 8;
          border-size = 2;
          default-timeout = 5000;
          font = "DroidSansM Nerd Font 11";
        };
      };

      # ── Idle handling ──────────────────────────────────────────────────────
      # Owns lock + display-off only. The suspend/hibernate chain is
      # DE-independent and owned by profiles/desktop/power.nix (its swayidle
      # unit sets logind IdleHint at 240s under any non-GNOME compositor). Lock
      # at 240s matches GNOME's idle-delay; screen off shortly after.
      hypridle = {
        enable = true;
        settings = {
          general = {
            lock_cmd = "${pkgs.procps}/bin/pidof hyprlock || ${pkgs.hyprlock}/bin/hyprlock";
            before_sleep_cmd = "${pkgs.systemd}/bin/loginctl lock-session";
            after_sleep_cmd = "${pkgs.hyprland}/bin/hyprctl dispatch dpms on";
          };
          listener = [
            {
              timeout = 240;
              on-timeout = "${pkgs.systemd}/bin/loginctl lock-session";
            }
            {
              timeout = 270;
              on-timeout = "${pkgs.hyprland}/bin/hyprctl dispatch dpms off";
              on-resume = "${pkgs.hyprland}/bin/hyprctl dispatch dpms on";
            }
          ];
        };
      };

      # ── Wallpaper ──────────────────────────────────────────────────────────
      hyprpaper = {
        enable = true;
        settings = {
          ipc = "on";
          splash = false;
          preload = [wallpaper];
          wallpaper = ["eDP-1,${wallpaper}"];
        };
      };

      # ── Session services ───────────────────────────────────────────────────
      hyprpolkitagent.enable = true; # GUI auth prompts (polkit)
      cliphist.enable = true; # clipboard-history store
      network-manager-applet.enable = true; # tray icon for Waybar's tray
    };

    # ── Theming ──────────────────────────────────────────────────────────────
    # Dark colour-scheme itself comes from users/common/appearance.nix (dconf,
    # read by GTK regardless of compositor); this just names a concrete theme,
    # icon set, and cursor for the Hyprland session.
    gtk = {
      enable = true;
      theme = {
        name = "Adwaita-dark";
        package = pkgs.gnome-themes-extra;
      };
      iconTheme = {
        name = "Adwaita";
        package = pkgs.adwaita-icon-theme;
      };
      cursorTheme = {
        name = "Adwaita";
        package = pkgs.adwaita-icon-theme;
        size = 24;
      };
    };
  };
}
