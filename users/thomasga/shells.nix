{
  # Common shell configuration
  programs = {
    zsh = {
      enable = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      
      initExtra = ''
        # Run neofetch on terminal startup
        neofetch
        
        # Any additional shell commands can go here
      '';
      
      shellAliases = {
        ll = "ls -la";
        l = "ls -l";
        ".." = "cd ..";
        "..." = "cd ../..";
      };
      
      plugins = [
        {
          name = "powerlevel10k";
          src = let
            version = "1.26.0";
          in {
            outPath = builtins.fetchTarball {
              url = "https://github.com/romkatv/powerlevel10k/archive/v${version}.tar.gz";
              sha256 = "sha256:0ifhf4mxbq9qp2mlhd6jhg4z7j77wz8lcqqswm6ify3s7r6g4ca";
            };
          };
          file = "powerlevel10k.zsh-theme";
        }
      ];
    };

    fish = {
      enable = false;  # Set to true if you prefer fish
      interactiveShellInit = ''
        # Run neofetch on terminal startup
        neofetch
      '';
      
      shellAliases = {
        ll = "ls -la";
        l = "ls -l";
        ".." = "cd ..";
        "..." = "cd ../..";
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
        mouse_hide_wait = 3.0;
        
        # Cursor
        cursor_shape = "beam";
        cursor_beam_thickness = 1.5;
        
        # Bell
        enable_audio_bell = false;
        visual_bell_duration = 0.0;
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
      enable = false;  # Set to true if you prefer alacritty over kitty
      
      settings = {
        window = {
          padding = { x = 10; y = 10; };
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
          normal = [
            "#282a36"  # black
            "#ff5555"  # red
            "#50fa7b"  # green
            "#f1fa8c"  # yellow
            "#bd93f9"  # blue
            "#ff79c6"  # magenta
            "#8be9fd"  # cyan
            "#bfbfbf"  # white
          ];
          bright = [
            "#4d4d4d"  # bright black
            "#ff6e6e"  # bright red
            "#69ff94"  # bright green
            "#ffffa5"  # bright yellow
            "#d6acff"  # bright blue
            "#ff92df"  # bright magenta
            "#a4ffff"  # bright cyan
            "#ffffff"  # bright white
          ];
        };
      };
    };
  };
}
