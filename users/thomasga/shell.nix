{pkgs, ...}: {
  custom.cli.shell = "fish";

  programs = {
    fish = {
      enable = true; # Added this to ensure fish is actually managed
      interactiveShellInit = ''
        set fish_greeting
      '';

      shellAliases = {
        cat = "bat";
        ll = "ls -la";
        l = "ls -l";
        ".." = "cd ..";
        "..." = "cd ../..";
      };

      functions = {
        ls = ''
          eza --icons=always $argv
        '';

        ll = ''
          ls -lah $argv
        '';

        lt = ''
          ll --tree --level=3 $argv
        '';
      };
    };

    # Terminal: Kitty
    kitty = {
      enable = true;
      theme = "Dracula";

      settings = {
        font_family = "Droid Sans Mono Nerd Font";
        font_size = 12;

        # Performance and behavior
        scrollback_lines = 10000;
        paste_actions = "quote-urls-at-prompt";

        # Mouse
        mouse_hide_wait = "3.0"; # Settings usually expect strings

        # Cursor
        cursor_shape = "beam";
        cursor_beam_thickness = "1.5";

        # Bell
        enable_audio_bell = false;
        visual_bell_duration = "0.0";
      };

      keybindings = {
        "ctrl+shift+c" = "copy_to_clipboard";
        "ctrl+shift+v" = "paste_from_clipboard";
        "ctrl+shift+n" = "new_window";
        "ctrl+shift+t" = "new_tab";
      };
    };

    # Terminal: Alacritty
    alacritty = {
      enable = false; # Set to true if you prefer alacritty over kitty

      settings = {
        window = {
          padding = {
            x = 10;
            y = 10;
          };
          opacity = 0.95;
          decorations = "full";
        };

        font = {
          normal = {
            family = "Droid Sans Mono Nerd Font";
            style = "Regular";
          };
          size = 12.0;
        };

        colors = {
          # Dracula theme
          primary = {
            background = "#282a36";
            foreground = "#f8f8f2";
          };
          normal = {
            black = "#282a36";
            red = "#ff5555";
            green = "#50fa7b";
            yellow = "#f1fa8c";
            blue = "#bd93f9";
            magenta = "#ff79c6";
            cyan = "#8be9fd";
            white = "#bfbfbf";
          };
          bright = {
            black = "#4d4d4d";
            red = "#ff6e6e";
            green = "#69ff94";
            yellow = "#ffffa5";
            blue = "#d6acff";
            magenta = "#ff92df";
            cyan = "#a4ffff";
            white = "#ffffff";
          };
        };
      };
    };
  };

  home.packages = with pkgs; [
    neofetch
    bat
    eza
  ];
}
