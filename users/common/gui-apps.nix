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
    };
  };

  home.packages = with pkgs; [
    mediawriter
    bitwarden-desktop
    google-chrome
    moonlight-qt
    signal-desktop
  ];

  # amdgpu invalidates GPU context on hibernate resume, crashing Signal's
  # Chromium GPU process (SIGTRAP). Override the .desktop entry to pass
  # --disable-gpu until fixed upstream.
  xdg.desktopEntries.signal-desktop = {
    name = "Signal";
    exec = "signal-desktop --disable-gpu %U";
    icon = "signal-desktop";
    comment = "Private messaging from your desktop";
    categories = ["Network" "InstantMessaging" "Chat"];
    mimeType = ["x-scheme-handler/sgnl" "x-scheme-handler/signalcaptcha"];
    terminal = false;
  };
}
