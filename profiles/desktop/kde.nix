{
  config,
  lib,
  pkgs,
  ...
}: {
  # KDE Plasma 6 session, active only when custom.desktop.environment = "kde"
  # (declared in modules/desktop.nix). Per this repo's model each DE owns its
  # own greeter (see profiles/desktop/gnome.nix); KDE brings SDDM rather than
  # reusing GDM, so GDM is entirely absent from the closure when this is
  # selected. The user-facing session config (panel, shortcuts, theme,
  # power) is home-manager in users/thomasga/kde.nix via plasma-manager.
  config = lib.mkIf (config.custom.desktop.environment == "kde") {
    environment = {
      # Trim Plasma's bundled extras we don't use. Konsole is dropped because we
      # use Ghostty; elisa/khelpcenter are unused. Kept deliberately: dolphin
      # (file manager), spectacle (screenshots), kwalletmanager (secret store),
      # systemsettings, plasma-systemmonitor.
      plasma6.excludePackages = with pkgs.kdePackages; [
        konsole
        elisa
        khelpcenter
      ];
      systemPackages = with pkgs.kdePackages; [
        # KWallet management UI (KWallet is the system keyring under Plasma).
        kwalletmanager
      ];
    };

    # dconf is still needed so GTK apps (Firefox, VS Code, etc.) pick up the
    # shared color-scheme key set in users/common/appearance.nix.
    programs.dconf.enable = true;

    services = {
      desktopManager.plasma6.enable = true;

      # KDE's own greeter, replacing GDM entirely when KDE is selected.
      displayManager.sddm = {
        enable = true;
        wayland.enable = true;
        autoNumlock = true;
      };
    };

    # KWallet is the desktop secret store under Plasma. kwallet-pam unlocks the
    # login wallet with the login password at SDDM sign-in — the KDE equivalent
    # of GDM's pam_gnome_keyring auto-unlock. Fingerprint sign-in provides no
    # password token, so a fingerprint-only login leaves the wallet locked until
    # the first password prompt; acceptable because the disk is LUKS-encrypted.
    security.pam.services.sddm.kwallet.enable = true;
  };
}
