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
    discord
    google-chrome
    # nixpkgs ships 1.19.0; bump to 1.21.1 to get the "Automatic" theme
    # (added in 1.20.0) that follows the system light/dark preference.
    (mailspring.overrideAttrs (_old: rec {
      version = "1.21.1";
      src = fetchurl {
        url = "https://github.com/Foundry376/Mailspring/releases/download/${version}/mailspring-${version}-amd64.deb";
        hash = "sha256-pyEWypqujSYYmbpUgcUMJoew4nIjE/dQWTVdYTxhmN4=";
      };
    }))
    edgetx
    moonlight-qt
    qgroundcontrol
    signal-desktop
  ];

  xdg.desktopEntries = {
    # amdgpu invalidates GPU context on hibernate resume, crashing Signal's
    # Chromium GPU process (SIGTRAP). Override the .desktop entry to pass
    # --disable-gpu until fixed upstream.
    signal-desktop = {
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
