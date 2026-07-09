_: {
  # Excalidraw has no native desktop package in nixpkgs; it's browser-only.
  # Launch the URL via xdg-open so it follows the system default browser,
  # same as the Onshape entry in gui-apps.nix.
  xdg.desktopEntries.excalidraw = {
    name = "Excalidraw";
    exec = "xdg-open https://excalidraw.com/";
    icon = "applications-graphics";
    comment = "Virtual whiteboard for sketching diagrams";
    categories = ["Graphics"];
    terminal = false;
  };
}
