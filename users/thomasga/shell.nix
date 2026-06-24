{pkgs, ...}: {
  custom.cli.shell = "fish";

  programs = {
    fish = {
      enable = true;
      interactiveShellInit = ''
        set fish_greeting

        if command -q connect-iq-sdk-manager
          set -l connect_iq_bin (connect-iq-sdk-manager sdk current-path --bin 2>/dev/null)
          if test -n "$connect_iq_bin" -a -d "$connect_iq_bin"
            fish_add_path --path "$connect_iq_bin"
          end
        end
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
