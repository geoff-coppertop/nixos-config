{pkgs, ...}: let
  # Community EasyEffects presets tuned for the Framework 13's thin,
  # down-firing speakers: https://github.com/ceiphr/ee-framework-presets
  # Pinned to a commit (not "main") so the fetch is reproducible; bump `rev`
  # and the per-file hashes together to pick up upstream changes.
  rev = "27885fe00c97da7c441358c7ece7846722fd12fa";

  fetchPreset = name: hash:
    pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/ceiphr/ee-framework-presets/${rev}/${name}.json";
      inherit hash;
    };
in {
  # roles/desktop/gnome.nix already sets programs.dconf.enable = true at the
  # system level, which the easyeffects daemon requires.
  services.easyeffects = {
    enable = true;
    # Framework 13 speakers are thin and lap use is the common case; the
    # on-table alternative (kieran_levin) is fetched below and can be
    # swapped in from the EasyEffects UI.
    preset = "lappy_mctopface";
  };

  # Fetched directly rather than routed through services.easyeffects.extraPresets
  # (which would round-trip the JSON through fromJSON/readFile, forcing an
  # import-from-derivation build during evaluation). Writing straight to
  # xdg.dataFile matches what that option does internally, just without the
  # re-serialization step.
  xdg.dataFile = {
    "easyeffects/output/gracefu.json".source = fetchPreset "gracefu" "sha256-neC6AJ0CsQhhhAGmhmGoQb7Dl0ZoszBGvmIm1S6BxI0=";
    "easyeffects/output/kieran_levin.json".source = fetchPreset "kieran_levin" "sha256-a1JJ4L3Dse21cxev0EeQ83rVc5JU/HFlo1CZTGTSt/M=";
    "easyeffects/output/lappy_mctopface.json".source = fetchPreset "lappy_mctopface" "sha256-Z9jEIeQTkWAK0e9WZeI75umZeRE3WuaVnw6vAby1jf4=";
    "easyeffects/output/philonmetal.json".source = fetchPreset "philonmetal" "sha256-sN5WgpvQrmZ+u/fOrznCbz3eJsFPXAmTSx7gHKn+WUo=";
  };
}
