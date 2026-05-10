{
  config,
  lib,
  ...
}: {
  config = lib.mkIf (config.custom.cli.shell == "fish") {
    programs.fish = {
      enable = true;
    };
  };
}
