{
  config,
  lib,
  ...
}: let
  inherit (lib) mkEnableOption mkIf optionalAttrs;
in {
  options.custom.flatpak.enable = mkEnableOption "declarative Flatpak management via nix-flatpak";

  config = mkIf config.custom.flatpak.enable {
    services.flatpak = {
      enable = true;

      remotes = [
        {
          name = "flathub";
          location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
        }
      ];

      packages = [
        "com.github.tchx84.Flatseal"
        "com.bambulab.BambuStudio"
      ];

      uninstallUnmanaged = true;

      update = {
        onActivation = true;
        auto = {
          enable = true;
          onCalendar = "weekly";
        };
      };
    };

    # On laptops, skip the scheduled update while on battery — same gating as
    # NAS backups and the NixOS auto-upgrade.
    systemd.services.flatpak-automatic-update.unitConfig = optionalAttrs config.custom.isLaptop {
      ConditionACPower = true;
    };
  };
}
