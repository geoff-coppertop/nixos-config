{pkgs, ...}: {
  programs.firefox = {
    enable = true;

    # Open the coppertop.ca landing page at startup and via the home button.
    # A policy (not a managed profile) so it applies without touching existing
    # profile data. Firefox has no native custom new-tab URL — that would need
    # an extension — so this covers startup and the home button, not new tabs.
    policies.Homepage = {
      URL = "https://coppertop.ca";
      StartPage = "homepage";
    };
  };

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
