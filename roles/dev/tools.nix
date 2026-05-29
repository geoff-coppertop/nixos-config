{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    # GitHub CLI — used directly and via git aliases (prc, prm, prs, prv)
    gh
  ];
}
