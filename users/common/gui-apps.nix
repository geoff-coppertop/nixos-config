{pkgs, ...}: {
  programs.firefox.enable = true;

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = "firefox.desktop";
      "x-scheme-handler/http" = "firefox.desktop";
      "x-scheme-handler/https" = "firefox.desktop";
      "x-scheme-handler/about" = "firefox.desktop";
      "x-scheme-handler/unknown" = "firefox.desktop";
      "application/pdf" = "firefox.desktop";
    };
  };

  home.packages = with pkgs; [
    mediawriter
    bitwarden-desktop
    discord
    google-chrome
    mailspring
    edgetx
    moonlight-qt
    qgroundcontrol
    signal-desktop
  ];

  xdg.desktopEntries = {
    # amdgpu invalidates GPU context on hibernate resume, crashing Signal's
    # Chromium GPU process (SIGTRAP). Override the .desktop entry to pass
    # --disable-gpu until fixed upstream.
    # Attribute name matches the upstream filename (signal.desktop) so this
    # entry overrides it via XDG_DATA_DIRS precedence rather than adding a dupe.
    signal = {
      name = "Signal";
      exec = "signal-desktop --disable-gpu %U";
      icon = "signal-desktop";
      comment = "Private messaging from your desktop";
      categories = ["Network" "InstantMessaging" "Chat"];
      mimeType = ["x-scheme-handler/sgnl" "x-scheme-handler/signalcaptcha"];
      terminal = false;
    };

    # Onshape is browser-only; launch the URL via xdg-open so it follows
    # the system default browser.
    onshape = {
      name = "Onshape";
      exec = "xdg-open https://cad.onshape.com/";
      icon = "applications-engineering";
      comment = "Cloud-native CAD";
      categories = ["Graphics" "Engineering"];
      terminal = false;
    };
  };
}
