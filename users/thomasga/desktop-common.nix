{
  lib,
  pkgs,
  ...
}: let
  localFile = import ../../lib/local-file.nix;

  # Same underlying file as users/thomasga/account.nix's `avatar` (consumed by
  # AccountsService/GDM); reuse its already-wrapped value instead of wrapping
  # the raw path a second time.
  account = import ./account.nix;

  # Fedora's space-shuttle wallpaper ships as JPEG XL; convert to PNG at build
  # time so we don't rely on runtime .jxl wallpaper support. Consumed by the
  # GNOME background (users/thomasga/gnome.nix) and, when added, by other
  # sessions' wallpaper tools.
  spaceShuttlePng =
    pkgs.runCommand "space-shuttle.png"
    {
      nativeBuildInputs = [pkgs.libjxl];
    }
    ''
      djxl ${localFile {path = ./files/wallpapers/space-shuttle.jxl;}} "$out"
    '';
in {
  # DE-independent desktop bits shared by every session. The per-DE home
  # configs (users/thomasga/gnome.nix, and future compositors) are gated on the
  # DE; anything neutral lives here so it isn't duplicated across (or trapped
  # inside) one of them.
  home = {
    file = {
      ".face".source = account.avatar;
      "Pictures/Wallpapers/space-shuttle.png".source = spaceShuttlePng;
    };

    activation = {
      ensureBuildsBookmark = lib.hm.dag.entryAfter ["writeBoundary"] ''
        bookmarksFile="$HOME/.config/gtk-3.0/bookmarks"
        mkdir -p "$(dirname "$bookmarksFile")"
        # Append only if absent so Nautilus can still manage other bookmarks freely
        if ! grep -qF "file://$HOME/builds" "$bookmarksFile" 2>/dev/null; then
          echo "file://$HOME/builds builds" >> "$bookmarksFile"
        fi
      '';

      # Steam silently drops .desktop shortcuts in ~/.local/share/applications/
      # for games we never asked to "Add to desktop". Auto-remove any entry whose
      # Exec= points to a steam://rungameid/ URI on every activation.
      purgeSteamGameShortcuts = lib.hm.dag.entryAfter ["writeBoundary"] ''
        for f in "$HOME/.local/share/applications/"*.desktop; do
          [ -e "$f" ] || continue
          if grep -q '^Exec=steam steam://rungameid/' "$f" 2>/dev/null; then
            rm -f "$f"
          fi
        done
      '';
    };
  };

  # Hide GTK SDK toy apps (side-effect of gtk3 being a runtime dep) and CLI
  # editors from every launcher (GNOME app grid and any future launcher alike).
  xdg.desktopEntries = {
    gtk3-demo = {
      name = "GTK3 Demo";
      noDisplay = true;
    };
    gtk3-icon-browser = {
      name = "GTK3 Icon Browser";
      noDisplay = true;
    };
    gtk3-widget-factory = {
      name = "GTK3 Widget Factory";
      noDisplay = true;
    };
    # vim/gvim are launched from Ghostty, not the launcher.
    vim = {
      name = "Vim";
      noDisplay = true;
    };
    gvim = {
      name = "GVim";
      noDisplay = true;
    };
  };
}
