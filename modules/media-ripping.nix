{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) genAttrs mkEnableOption mkIf mkOption types;
  cfg = config.custom.mediaRipping;
in {
  options.custom.mediaRipping = {
    enable = mkEnableOption "manual optical ripping tools (MakeMKV, HandBrake, whipper)";

    users = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Users to add to the cdrom group for optical-drive access.";
    };
  };

  # Manual/fallback toolkit. The automated pipeline lives in the autoRip module
  # (Automatic Ripping Machine); these tools cover discs it misidentifies or
  # fails on, and whipper for accurate lossless CD rips.
  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      makemkv # Blu-ray/DVD decryption and remux to MKV (GUI + makemkvcon)
      handbrake # transcode ripped titles for delivery
      whipper # accurate, secure CD ripping to FLAC
      libdvdcss # CSS-encrypted DVD access for HandBrake
    ];

    # Optical drives are owned by the cdrom group; add operators so the tools
    # reach the drive without root.
    users.users = genAttrs cfg.users (_: {extraGroups = ["cdrom"];});
  };
}
