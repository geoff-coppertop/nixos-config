{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule (finalAttrs: {
  pname = "connect-iq-sdk-manager-cli";
  version = "0.8.4";

  src = fetchFromGitHub {
    owner = "lindell";
    repo = "connect-iq-sdk-manager-cli";
    tag = "v${finalAttrs.version}";
    hash = "sha256-NEzy+lvBAvrapR6lq7k8b/3N4Os3Q7Wx4Vfv5qcjJiU=";
  };

  vendorHash = "sha256-hkYgYVOYx18GMF8RpiRBmNtwd+uhZn197LlpdwfqW8c=";

  # tests/live_test.go hits the network and a real $HOME, neither available in the build sandbox
  doCheck = false;

  # go build names the root package binary after the module path's last
  # segment (connect-iq-sdk-manager-cli); upstream only gets the shorter
  # name via a goreleaser rename, which buildGoModule doesn't replicate.
  postInstall = ''
    mv $out/bin/connect-iq-sdk-manager-cli $out/bin/connect-iq-sdk-manager
  '';

  meta = {
    description = "Non-interactive CLI replacement for Garmin's Connect IQ SDK Manager GUI";
    homepage = "https://github.com/lindell/connect-iq-sdk-manager-cli";
    license = lib.licenses.asl20;
    mainProgram = "connect-iq-sdk-manager";
    platforms = lib.platforms.unix;
  };
})
