{ config, pkgs, ... }:

let
  spaceShuttlePng = pkgs.runCommand "space-shuttle.png"
    {
      nativeBuildInputs = [ pkgs.libjxl ];
    }
    ''
      djxl ${./files/wallpapers/space-shuttle.jxl} "$out"
    '';
in
{
  home.file."Pictures/Wallpapers/space-shuttle.png".source = spaceShuttlePng;

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
  };
}
