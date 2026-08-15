{config, ...}: {
  # GPU vendor selection is host-specific (mirrors enterprise-d's amdgpu line).
  # hardware.graphics (incl. 32-bit for Proton/SteamVR) comes from
  # modules/gaming.nix via custom.gaming.enable.
  services.xserver.videoDrivers = ["nvidia"];

  hardware.nvidia = {
    modesetting.enable = true;
    # RTX 4080 Super is Ada Lovelace — NVIDIA's open kernel modules are the
    # recommended path for Turing and newer.
    open = true;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    # Desktop, always on AC — no runtime/suspend power management needed.
    powerManagement.enable = false;
  };
}
