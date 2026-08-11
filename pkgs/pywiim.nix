# pywiim -- the Python client library the "wiim" Home Assistant custom
# component (pkgs/home-assistant-wiim.nix) requires. Built against
# home-assistant's own python3Packages passthru, not the general top-level
# python3Packages, since a custom component's Python deps must share HA's
# interpreter/package environment to avoid version conflicts (confirmed via
# nixpkgs' own custom-components convention, e.g. pkgs/servers/home-assistant/
# custom-components/powercalc/package.nix, and pkgs/servers/home-assistant/
# default.nix's own passthru block, which is where python3Packages actually
# lives -- not nested under a "python" attribute, despite that being the more
# commonly (mis)quoted path).
{
  lib,
  home-assistant,
}:
home-assistant.python3Packages.buildPythonPackage rec {
  pname = "pywiim";
  version = "2.3.0";
  pyproject = true;

  src = home-assistant.python3Packages.fetchPypi {
    inherit pname version;
    # Real hash as reported by Nix's own hash-mismatch error from an actual
    # build. An earlier value derived by hex-decoding/re-encoding PyPI's
    # JSON API sha256 digest (fetched via WebFetch) turned out to be wrong --
    # WebFetch summarizes page content through a smaller model rather than
    # extracting raw digests reliably, so it isn't trustworthy for anything
    # this precision-sensitive. Nix's own mismatch report is authoritative.
    hash = "sha256-/SOxSvddmVgqpAgnE5HdGHuVD/JYVbQA9/4Wngmbkr0=";
  };

  build-system = [home-assistant.python3Packages.setuptools];

  dependencies = with home-assistant.python3Packages; [
    aiohttp
    pydantic
    async-upnp-client
    m3u8
    mutagen
  ];

  # Runtime dependency of the wiim HA component only -- not built/tested
  # standalone here.
  doCheck = false;

  pythonImportsCheck = ["pywiim"];

  meta = {
    description = "Async Python client for WiiM and LinkPlay-based audio devices";
    homepage = "https://github.com/mjcumming/pywiim";
    license = lib.licenses.mit;
  };
}
