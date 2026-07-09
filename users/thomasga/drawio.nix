{
  pkgs,
  lib,
  ...
}: {
  home.packages = [pkgs.drawio];

  # xdg.dataFile only drops the raw glob XML into ~/.local/share/mime/packages/;
  # home-manager doesn't compile it into mime.cache, so the *.drawio glob
  # registration below is inert until update-mime-database runs against it.
  home.activation.drawioMimeDatabase = lib.hm.dag.entryAfter ["writeBoundary"] ''
    $DRY_RUN_CMD ${pkgs.shared-mime-info}/bin/update-mime-database $VERBOSE_ARG "$HOME/.local/share/mime"
  '';

  xdg = {
    # draw.io diagrams embedded in the Obsidian vault use the .drawio
    # extension, which isn't in the shared-mime-info database by default.
    # Register it so file managers and "Open" dialogs know to hand it to
    # draw.io instead of treating it as plain XML/text.
    dataFile."mime/packages/drawio.xml".text = ''
      <?xml version="1.0" encoding="UTF-8"?>
      <mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
        <mime-type type="application/vnd.jgraph.mxfile">
          <comment>draw.io diagram</comment>
          <glob pattern="*.drawio"/>
          <glob pattern="*.dio"/>
        </mime-type>
      </mime-info>
    '';

    mimeApps = {
      enable = true;
      defaultApplications = {
        "application/vnd.jgraph.mxfile" = "drawio.desktop";
      };
    };

    # Upstream's desktop entry uses the lowercase package name ("drawio") as
    # its display Name, and references the icon by theme name ("drawio")
    # rather than a path — which falls back to GNOME's generic app icon in
    # the app grid when hicolor lookup doesn't resolve it. Override via
    # XDG_DATA_DIRS precedence (same trick as the signal.desktop override in
    # users/common/gui-apps.nix), pointing icon at the store SVG directly so
    # GTK/Gio loads it without depending on icon-theme cache resolution.
    desktopEntries.drawio = {
      name = "draw.io";
      comment = "draw.io desktop";
      exec = "drawio %U";
      icon = "${pkgs.drawio}/share/icons/hicolor/scalable/apps/drawio.svg";
      categories = ["Graphics"];
      mimeType = ["application/vnd.jgraph.mxfile" "application/vnd.visio"];
      terminal = false;
      settings.StartupWMClass = "draw.io";
    };
  };
}
