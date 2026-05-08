{ pkgs, agenixCli }:

pkgs.mkShell {
  packages = [
    agenixCli
    pkgs.age
    pkgs.alejandra
    pkgs.deadnix
    pkgs.nodePackages.markdownlint-cli
    pkgs.pre-commit
    pkgs.statix
  ];
}
