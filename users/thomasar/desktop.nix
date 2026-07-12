{pkgs, ...}: {
  # GUI profile for the low-privilege test account: the shared shell/git
  # look-and-feel, modern-unix tooling, and shared GUI apps, none of
  # thomasga's personal config (git identity, SSH keys, agenix secrets,
  # VS Code, dev tooling).
  imports = [
    ../common/base.nix
    ../common/cli
    ../common/gui-apps.nix
  ];

  home.packages = [pkgs.vim];
}
