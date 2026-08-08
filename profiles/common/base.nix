{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) optionalAttrs;
  keepGenerations = toString config.custom.nix.gc.keepGenerations;
in {
  nix = {
    settings = {
      experimental-features = ["nix-command" "flakes"];

      # Remote deploys (nixos-rebuild --target-host) push locally-built
      # store paths over SSH as the login user. The nix daemon only
      # accepts unsigned paths from trusted-users (default: root only) —
      # without this, deploying to any host over SSH as a non-root user
      # fails with "lacks a signature by a trusted key". Confirmed live
      # deploying to defiant as thomasga.
      trusted-users = ["root" "@wheel"];
    };

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
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

  systemd = {
    # nix-gc scans the entire store and is CPU-intensive; run it at idle
    # priority so a background collection can't spike temperatures or
    # starve interactive work.
    #
    # preStart prunes by count before nix-gc prunes by age, giving OR
    # semantics: a generation is dropped if there are more than
    # custom.nix.gc.keepGenerations OR it is older than 30 days.
    services.nix-gc = {
      serviceConfig = {
        Nice = 19;
        CPUSchedulingPolicy = "idle";
        IOSchedulingClass = "idle";
      };
      preStart = ''
        ${pkgs.nix}/bin/nix-env \
          -p /nix/var/nix/profiles/system \
          --delete-generations +${keepGenerations} 2>/dev/null || true
        for p in /nix/var/nix/profiles/per-user/*/home-manager; do
          [ -e "$p" ] || continue
          ${pkgs.nix}/bin/nix-env -p "$p" --delete-generations +${keepGenerations} 2>/dev/null || true
        done
      '';
    };

    # On laptops, skip the upgrade while on battery — same gating as NAS backups.
    services.nixos-upgrade.unitConfig = optionalAttrs config.custom.isLaptop {
      ConditionACPower = true;
    };

    # Electron and other large processes dump multi-GB core files that can
    # take 60+ seconds to process, blocking login session teardown. Cap
    # size so processing stays fast while keeping dumps inspectable.
    coredump.settings.Coredump = {
      ProcessSizeMax = "256M";
      ExternalSizeMax = "256M";
    };
  };

  time.timeZone = "America/Edmonton";
  i18n.defaultLocale = "en_CA.UTF-8";

  boot.kernelPackages = pkgs.linuxPackages_latest;

  fonts.packages = with pkgs; [
    nerd-fonts.droid-sans-mono
  ];

  services.journald.extraConfig = "Storage=persistent";

  environment.systemPackages = with pkgs; [
    pciutils
    usbutils
    # Confirmed live: SSHing into a headless host from a Ghostty terminal
    # (TERM=xterm-ghostty) breaks terminfo-dependent commands like `clear`
    # ("unknown terminal type") since the remote machine has no matching
    # terminfo entry. ghostty.terminfo is a dedicated package output for
    # exactly this — installing the terminfo without the GUI app itself.
    ghostty.terminfo
  ];

  documentation.nixos.enable = false;
}
