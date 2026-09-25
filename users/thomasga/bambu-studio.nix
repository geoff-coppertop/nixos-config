{
  lib,
  pkgs,
  ...
}: let
  # Trusts reliant's Bambuddy virtual-printer CA — see pkgs/bambu-studio.nix.
  bambu-studio = import ../../pkgs/bambu-studio.nix {inherit pkgs;};
in {
  home.packages = [bambu-studio];

  xdg.desktopEntries = {
    # Same icon-by-theme-name issue as OrcaSlicer's own override below —
    # point at the PNG directly.
    BambuStudio = {
      name = "BambuStudio";
      genericName = "3D Printing Software";
      exec = "bambu-studio %U";
      icon = "${bambu-studio}/share/icons/hicolor/192x192/apps/BambuStudio.png";
      terminal = false;
      categories = ["Graphics" "3DGraphics" "Engineering"];
      mimeType = [
        "model/stl"
        "model/3mf"
        "application/vnd.ms-3mfdocument"
        "application/prs.wavefront-obj"
        "application/x-amf"
        "x-scheme-handler/bambustudio"
        "model/step"
      ];
      settings.StartupWMClass = "bambu-studio";
    };
  };

  # Ignores the XDG color-scheme portal; seed dark_color_mode directly
  # (docs/desktop.md § Bambu Studio).
  home.activation.bambuStudioColorScheme = lib.hm.dag.entryAfter ["writeBoundary"] ''
    _bbs_cfg="$HOME/.config/BambuStudio/BambuStudio.conf"
    if [ -f "$_bbs_cfg" ]; then
      if grep -q '"dark_color_mode"' "$_bbs_cfg"; then
        sed -i 's/"dark_color_mode": "[01]"/"dark_color_mode": "1"/' "$_bbs_cfg"
      fi
    fi
  '';
}
