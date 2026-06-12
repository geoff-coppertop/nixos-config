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
  };

  home.packages = with pkgs; [
    fastfetch
    bat
    eza
  ];
}
