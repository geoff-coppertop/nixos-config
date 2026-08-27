# Declares which desktop environment / Wayland compositor a host runs. Read
# by profiles/desktop/<de>.nix (system, `lib.mkIf`-gated) and
# users/<name>/<de>.nix (home, gated on osConfig.custom.desktop.environment) —
# it belongs to neither individually. To add a desktop: add its value to this
# enum, add a gated profiles/desktop/<de>.nix and users/<name>/<de>.nix, and
# import the system file from profiles/desktop/default.nix.
{lib, ...}: {
  options.custom.desktop.environment = lib.mkOption {
    type = lib.types.enum ["gnome" "hyprland"];
    default = "gnome";
    description = "Desktop environment / Wayland compositor to install and enable on this host.";
  };
}
