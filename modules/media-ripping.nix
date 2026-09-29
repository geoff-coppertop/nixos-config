{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) genAttrs mkEnableOption mkIf mkOption types;
  cfg = config.custom.mediaRipping;

  uid = toString cfg.uid;
  gid = toString cfg.gid;

  # import-disc has no metadata source of its own (no TMDB lookup like ARM,
  # no job database) -- IMPORT_ROOT/IMPORT_UID/IMPORT_GID are baked in here
  # (not left for the operator to type every time) so the only decision left
  # at invocation is the one thing that genuinely can't be automated: what
  # the disc actually contains. custom.mediaSort's importDir leg reads the
  # same IMPORT_ROOT by option, not by parsing this script.
  importDisc = pkgs.writeShellApplication {
    name = "import-disc";
    runtimeInputs = with pkgs; [util-linux eject coreutils findutils];
    text = ''
      export IMPORT_ROOT=${lib.escapeShellArg cfg.importDir} IMPORT_UID=${uid} IMPORT_GID=${gid}
      ${builtins.readFile ./import-disc.sh}
    '';
  };
in {
  options.custom.mediaRipping = {
    enable = mkEnableOption "manual optical ripping and import tools (MakeMKV, HandBrake, whipper, import-disc)";

    users = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Users to add to the cdrom group for optical-drive access.";
    };

    importDir = mkOption {
      type = types.str;
      default = "/var/lib/media-import";
      description = "Local staging root import-disc writes into (movies/<title>/ or tv/<show>/Season N/) and custom.mediaSort's importDir leg reads from -- same value belongs in both.";
    };

    uid = mkOption {
      type = types.int;
      default = 1000;
      description = "UID import-disc's copied files are chowned to; needs to match whatever reads importDir back out (custom.mediaSort's uid).";
    };

    gid = mkOption {
      type = types.int;
      default = 1000;
      description = "GID import-disc's copied files are chowned to.";
    };
  };

  # Manual/fallback toolkit. The automated pipeline lives in the autoRip module
  # (Automatic Ripping Machine); these tools cover discs it misidentifies or
  # fails on, whipper for accurate lossless CD rips, and import-disc for data
  # discs (e.g. DVDs already holding DivX/Xvid rips) that need copying rather
  # than decrypting/transcoding. import-disc's own output still needs
  # custom.mediaSort.importDir pointed at the same importDir to actually reach
  # the library -- this module only stages it locally.
  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      makemkv # Blu-ray/DVD decryption and remux to MKV (GUI + makemkvcon)
      handbrake # transcode ripped titles for delivery
      whipper # accurate, secure CD ripping to FLAC
      libdvdcss # CSS-encrypted DVD access for HandBrake
      importDisc # mount a data disc and copy existing video files
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.importDir} 0775 ${uid} ${gid} -"
      "d ${cfg.importDir}/movies 0775 ${uid} ${gid} -"
      "d ${cfg.importDir}/tv 0775 ${uid} ${gid} -"
    ];

    # Optical drives are owned by the cdrom group; add operators so the tools
    # reach the drive without root.
    users.users = genAttrs cfg.users (_: {extraGroups = ["cdrom"];});
  };
}
