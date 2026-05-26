{pkgs, ...}: {
  custom.cli.shell = "fish";

  programs = {
    fish = {
      enable = true;
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
        fish_greeting = ''
          fastfetch
        '';

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

    # Terminal: Ghostty
    ghostty = {
      enable = true;

      settings = {
        font-family = "DroidSansM Nerd Font Mono";
        font-size = 12;
        background-opacity = 0.95;
        window-padding-x = 10;
        window-padding-y = 10;
        theme = "Dracula";
      };
    };
  };

  home.packages = with pkgs; [
    fastfetch
    bat
    eza
  ];
}
