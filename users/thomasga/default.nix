{
  imports = [
    ../common/base.nix
    ../common/gui-apps.nix
    ./gnome.nix
    ./vscode.nix
    ./secrets.nix
  ];

  programs.git = {
    userName = "Geoffrey Thomas";
    userEmail = "you@example.com";
  };
}
