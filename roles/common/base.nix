{pkgs, ...}: let
  keepGenerations = 10;
in {
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
  ];
}
