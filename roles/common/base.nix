{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkOption optionalAttrs types;
  keepGenerations = 10;
in {
  options.custom.isLaptop = mkOption {
    type = types.bool;
    default = false;
    description = "Whether this host runs on battery and should gate AC-power-sensitive maintenance jobs (backups, upgrades, Flatpak updates).";
  };

  config = {
    nix.settings.experimental-features = ["nix-command" "flakes"];

    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };

    # nix-gc scans the entire store and is CPU-intensive; run it at idle priority
    # so a background collection can't spike temperatures or starve interactive work.
    #
    # preStart prunes by count before nix-gc prunes by age, giving OR semantics:
    # a generation is dropped if there are more than keepGenerations OR it is older
    # than 30 days.
    systemd.services.nix-gc = {
      serviceConfig = {
        Nice = 19;
        CPUSchedulingPolicy = "idle";
        IOSchedulingClass = "idle";
      };
      preStart = ''
        ${pkgs.nix}/bin/nix-env \
          -p /nix/var/nix/profiles/system \
          --delete-generations +${toString keepGenerations} 2>/dev/null || true
        for p in /nix/var/nix/profiles/per-user/*/home-manager; do
          [ -e "$p" ] || continue
          ${pkgs.nix}/bin/nix-env -p "$p" --delete-generations +${toString keepGenerations} 2>/dev/null || true
        done
      '';
    };

    # Fetch from GitHub and stage the new build as the next boot entry weekly.
    # operation = "boot" means no automatic reboot; the user reboots at their
    # convenience. The flake target is derived from the machine's hostname so
    # this applies to every host without per-machine configuration.
    system.autoUpgrade = {
      enable = true;
      flake = "github:geoff-coppertop/nixos-config#${config.networking.hostName}";
      operation = "boot";
      allowReboot = false;
      dates = "weekly";
      randomizedDelaySec = "45min";
    };

    # On laptops, skip the upgrade while on battery — same gating as NAS backups.
    systemd.services.nixos-upgrade.unitConfig = optionalAttrs config.custom.isLaptop {
      ConditionACPower = true;
    };

    time.timeZone = "America/Edmonton";
    i18n.defaultLocale = "en_CA.UTF-8";

    boot.kernelPackages = pkgs.linuxPackages_latest;

    fonts.packages = with pkgs; [
      nerd-fonts.droid-sans-mono
    ];

    services.journald.extraConfig = "Storage=persistent";

    # Electron and other large processes dump multi-GB core files that can take
    # 60+ seconds to process, blocking login session teardown. Cap size so
    # processing stays fast while keeping dumps inspectable.
    systemd.coredump.settings.Coredump = {
      ProcessSizeMax = "256M";
      ExternalSizeMax = "256M";
    };

    environment.systemPackages = with pkgs; [
      pciutils
      usbutils
    ];

    documentation.nixos.enable = false;
  };
}
