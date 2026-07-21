{lib, ...}: {
  # Selects which desktop environment / Wayland compositor is installed and
  # enabled. GDM (roles/desktop/login.nix) is the login manager regardless and
  # is always present; only the session it launches changes. The matching home-
  # manager config is gated on osConfig.custom.desktop.environment in
  # users/<name>/gnome.nix.
  #
  # To add another environment: add its value to this enum, add a gated
  # roles/desktop/<de>.nix (system) and users/<name>/<de>.nix (home) that each
  # `lib.mkIf (… == "<de>")`, and import the system file below.
  options.custom.desktop.environment = lib.mkOption {
    type = lib.types.enum ["gnome"];
    default = "gnome";
    description = "Desktop environment / Wayland compositor to install and enable on this host.";
  };

  imports = [
    ./audio.nix
    ./gnome.nix
    ./login.nix
    ./power.nix
  ];
}
