# Declares which desktop environment / Wayland compositor a host runs. Read
# by profiles/desktop/<de>.nix (system, `lib.mkIf`-gated) and
# users/<name>/<de>.nix (home, gated on osConfig.custom.desktop.environment) —
# it belongs to neither individually. To add a desktop: add its value to this
# enum, add a gated profiles/desktop/<de>.nix and users/<name>/<de>.nix, and
# import the system file from profiles/desktop/default.nix.
{lib, ...}: {
  options.custom.desktop.environment = lib.mkOption {
    type = lib.types.enum ["gnome" "kde"];
    default = "gnome";
    description = "Desktop environment / Wayland compositor to install and enable on this host.";
  };

  # Whether the DE's panel/dock should autohide. Host-scoped rather than
  # hardcoded in a DE's home config, because the right default depends on the
  # screen this specific host has, not on which DE is selected — a future KDE
  # host with a larger display may want the panel always visible instead.
  # Consumed by users/<name>/kde.nix via osConfig; GNOME's dash-to-dock
  # autohide is not (yet) wired to this option.
  options.custom.desktop.autohidePanel = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Autohide the desktop panel/dock. Set true on small-screen hosts.";
  };
}
