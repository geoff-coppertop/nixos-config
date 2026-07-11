{
  pkgs,
  agenixCli,
}:
pkgs.mkShell {
  packages = [
    agenixCli
    pkgs.age
    pkgs.alejandra
    pkgs.deadnix
    pkgs.markdownlint-cli
    pkgs.pre-commit
    pkgs.python3
    pkgs.statix
  ];
}
