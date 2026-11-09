{
  pkgs,
  osConfig ? null,
  ...
}: let
  app = "onlyoffice-desktopeditors.desktop";
  word = [
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    "application/msword"
    "application/vnd.oasis.opendocument.text"
  ];
  sheet = [
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    "application/vnd.ms-excel"
    "application/vnd.oasis.opendocument.spreadsheet"
  ];
  slides = [
    "application/vnd.openxmlformats-officedocument.presentationml.presentation"
    "application/vnd.ms-powerpoint"
    "application/vnd.oasis.opendocument.presentation"
  ];
in {
  # Its FHS sandbox only sees fonts passed here; reuse the system's. Standalone has none.
  home.packages = [
    (pkgs.onlyoffice-desktopeditors.override {
      extraFontPackages =
        if osConfig == null
        then []
        else osConfig.fonts.packages;
    })
  ];

  xdg.mimeApps = {
    enable = true;
    defaultApplications = builtins.listToAttrs (map (t: {
      name = t;
      value = app;
    }) (word ++ sheet ++ slides));
  };
}
