{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:
buildNpmPackage {
  pname = "obsidian-local-rest-api";
  version = "4.1.3";

  src = fetchFromGitHub {
    owner = "coddingtonbear";
    repo = "obsidian-local-rest-api";
    rev = "4.1.3";
    # nix-prefetch-github coddingtonbear obsidian-local-rest-api --rev 4.1.3
    hash = lib.fakeHash;
  };

  # cd $(nix-build -E '(import <nixpkgs> {}).callPackage ./pkgs/obsidian-local-rest-api.nix {}' --no-out-link 2>&1 | grep 'got:' | awk '{print $2}')
  # OR: prefetch-npm-deps <src>/package-lock.json
  npmDepsHash = lib.fakeHash;

  buildPhase = ''
    node esbuild.config.mjs production
  '';

  installPhase = ''
    mkdir -p $out
    install -m 644 main.js manifest.json styles.css $out/
  '';

  meta = {
    description = "Secure REST API and MCP server for Obsidian vaults";
    homepage = "https://github.com/coddingtonbear/obsidian-local-rest-api";
    license = lib.licenses.mit;
  };
}
