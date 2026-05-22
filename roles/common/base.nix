{pkgs, ...}: {
  nix.settings.experimental-features = ["nix-command" "flakes"];
  time.timeZone = "America/Edmonton";
  i18n.defaultLocale = "en_CA.UTF-8";

  boot.kernelPackages = pkgs.linuxPackages_latest;

  fonts.packages = with pkgs; [
    nerd-fonts.droid-sans-mono
  ];

  services.journald.extraConfig = "Storage=persistent";
}
