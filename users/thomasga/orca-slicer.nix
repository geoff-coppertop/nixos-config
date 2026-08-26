{pkgs, ...}: {
  home.packages = [pkgs.orca-slicer];

  xdg.desktopEntries = {
    # Upstream's desktop entry references the icon by theme name
    # ("OrcaSlicer") rather than a path, which falls back to GNOME's generic
    # app icon in the app grid because hicolor lookup doesn't resolve it
    # through the home-manager profile — same class of issue as the drawio
    # override below. nixpkgs ships no scalable SVG for it, only PNGs, so
    # point at the largest one (192px) directly instead of a theme name.
    # Attribute name matches the upstream filename
    # (com.orcaslicer.OrcaSlicer.desktop) so this entry overrides it via
    # XDG_DATA_DIRS precedence rather than adding a dupe.
    "com.orcaslicer.OrcaSlicer" = {
      name = "OrcaSlicer";
      genericName = "3D Printing Software";
      exec = "orca-slicer %U";
      icon = "${pkgs.orca-slicer}/share/icons/hicolor/192x192/apps/OrcaSlicer.png";
      terminal = false;
      categories = ["Graphics" "3DGraphics" "Engineering"];
      mimeType = [
        "model/stl"
        "model/3mf"
        "application/vnd.ms-3mfdocument"
        "application/prs.wavefront-obj"
        "application/x-amf"
        "x-scheme-handler/orcaslicer"
        "model/step"
      ];
      settings.StartupWMClass = "orca-slicer";
    };
  };
}
