_: let
  nas = import ../../lib/nas.nix;
  thomasga = import ../../users/thomasga/account.nix;
in {
  imports = [
    ./hardware.nix
    ./nvidia.nix
    ./disko.nix
    ./secrets.nix

    ../../profiles/common
    ../../profiles/desktop
    ../../profiles/dev

    ../../modules
  ];

  custom = {
    # "input": cough-button evdev reader; "dialout": SimHub's Arduino serial.
    users.thomasga = thomasga // {groups = ["wheel" "networkmanager" "plugdev" "input" "dialout"];};

    gaming.enable = true;
    flatpak.enable = true;
    vr.enable = true;
    wineGaming.enable = true;
    gameStreaming.enable = true;
    simagic.enable = true;

    # Same Wi-Fi networks as enterprise-d (agt-home/iot/work). This desktop
    # connects primarily over Ethernet, which NetworkManager prefers
    # automatically (lower route metric) whenever the cable is present; Wi-Fi is
    # the fallback. Eval is fine now (the wifi/*.age files exist), but they are
    # encrypted for enterprise-d only — re-key them to include stargazer's host
    # key at provisioning or they will not decrypt at activation. See README.
    wifi.enable = true;

    btrfs.enable = true;
    fwupd.enable = true;
    secureBoot.enable = true;
    snapper.enable = true;
    tpmLuks.enable = true;

    # backups, networkDrives, and the SSH-identity/GitHub-token secrets stay off
    # until stargazer's host key is enrolled and its per-host .age files exist —
    # enabling them now would reference secrets that do not exist yet. See README.
  };

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  networking.hostName = "stargazer";
  networking.hosts.${nas.ip} = [nas.host];

  # bitwarden-desktop is still pinned to electron_39 upstream (EOL, no more
  # security patches); nixpkgs marks it insecure. Known, currently-open
  # packaging lag (nixpkgs#529107, nixpkgs#526914) — remove this once
  # bitwarden-desktop is rebuilt against a supported electron release. Same
  # allowance as hosts/enterprise-d/configuration.nix, needed here because
  # this host also pulls in users/common/gui-apps.nix.
  nixpkgs.config.permittedInsecurePackages = ["electron-39.8.10"];

  system.stateVersion = "25.11";
}
