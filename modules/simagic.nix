{
  config,
  lib,
  ...
}: let
  inherit (lib) mkEnableOption mkIf;
in {
  options.custom.simagic.enable = mkEnableOption "SIMAGIC wheelbase force feedback (out-of-tree simagic-ff kernel module)";

  # The FFB half of the SIMAGIC stack is declarative: an out-of-tree kernel
  # module built against the host kernel. The vendor config app (Sim Pro
  # Manager) needs raw USB and does not run under Wine — firmware and
  # telemetry-driven effects are handled off-box (see hosts/stargazer/README.md,
  # which also covers the SDL_JOYSTICK_WHEEL_DEVICES hint if Proton needs it).
  config = mkIf config.custom.simagic.enable {
    boot.extraModulePackages = [
      (config.boot.kernelPackages.callPackage ../pkgs/simagic-ff.nix {})
    ];
  };
}
