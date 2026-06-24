{
  config,
  lib,
  pkgs,
  ...
}: {
  options.custom.binCompat.enable = lib.mkEnableOption "/bin/bash compat symlink for non-Nix binaries with a hardcoded #!/bin/bash shebang";

  config = lib.mkIf config.custom.binCompat.enable {
    system.activationScripts.binbash = lib.stringAfter ["usrbinenv"] ''
      mkdir -m 0755 -p /bin
      ln -sf ${pkgs.bash}/bin/bash /bin/bash
    '';
  };
}
