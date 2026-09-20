# See docs/smart-home.md § Bambuddy.
{
  lib,
  buildHomeAssistantComponent,
  fetchFromGitHub,
  home-assistant,
}:
buildHomeAssistantComponent rec {
  owner = "Spegeli";
  domain = "bambuddy";
  # manifest.json's version, and the tag.
  version = "2026.05.17";

  src = fetchFromGitHub {
    inherit owner;
    repo = "hacs_bambuddy";
    tag = "v${version}";
    hash = "sha256-kuTaejXG38TQLwJP7DBkSNaDqcgR+kRw1M6Ip+JTjEA=";
  };

  # Listed despite HA core already having it -- see § HACS Components.
  dependencies = [home-assistant.python3Packages.aiohttp];

  meta = {
    description = "Bambuddy integration for Home Assistant: printer telemetry, camera, and print controls";
    homepage = "https://github.com/Spegeli/hacs_bambuddy";
    changelog = "https://github.com/Spegeli/hacs_bambuddy/releases/tag/v${version}";
    license = lib.licenses.mit;
  };
}
