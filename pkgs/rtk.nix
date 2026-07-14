{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "rtk";
  version = "0.43.0";

  src = fetchFromGitHub {
    owner = "rtk-ai";
    repo = "rtk";
    tag = "v${finalAttrs.version}";
    # Fill in on first build: `nix build .#nixosConfigurations.enterprise-d...`
    # fails with the expected hash; paste it here.
    hash = lib.fakeHash;
  };

  # Fill in on first build the same way as `hash` above.
  cargoHash = lib.fakeHash;

  # The integration tests (tests/guard_integration_test.rs) shell out to a real
  # `git` and read $HOME, neither of which exists in the build sandbox. The
  # binary itself is exercised at runtime by the Claude Code hook, so skip them.
  doCheck = false;

  meta = {
    description = "Rust Token Killer — CLI proxy that filters and compresses command output to cut LLM token usage";
    homepage = "https://github.com/rtk-ai/rtk";
    license = lib.licenses.asl20;
    mainProgram = "rtk";
    platforms = lib.platforms.unix;
  };
})
