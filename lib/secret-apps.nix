{ pkgs, agenixCli }:

let
  secretEdit = pkgs.writeShellApplication {
    name = "secret-edit";
    runtimeInputs = [ agenixCli pkgs.coreutils pkgs.git pkgs.gnugrep ];
    text = ''
      set -euo pipefail

      repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
      cd "$repo_root"

      if [[ ! -f flake.nix || ! -f secrets/secrets.nix ]]; then
        echo "Run this command from the nixos-config repository root." >&2
        exit 1
      fi

      if [[ $# -ne 1 ]]; then
        echo "Usage: nix run .#secret-edit -- secrets/<name>.age" >&2
        exit 1
      fi

      secret_file="$1"

      if [[ "$secret_file" != secrets/*.age ]]; then
        echo "Secret path must live under secrets/ and end with .age." >&2
        exit 1
      fi

      if grep -q 'age1REPLACE_ME' secrets/secrets.nix; then
        echo "Replace the placeholder public key in secrets/secrets.nix before editing secrets." >&2
        exit 1
      fi

      mkdir -p "$(dirname "$secret_file")"
      RULES="$repo_root/secrets/secrets.nix" agenix -e "$secret_file"
    '';
  };

  secretRekey = pkgs.writeShellApplication {
    name = "secret-rekey";
    runtimeInputs = [ agenixCli pkgs.git pkgs.gnugrep ];
    text = ''
      set -euo pipefail

      repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
      cd "$repo_root"

      if [[ ! -f flake.nix || ! -f secrets/secrets.nix ]]; then
        echo "Run this command from the nixos-config repository root." >&2
        exit 1
      fi

      if grep -q 'age1REPLACE_ME' secrets/secrets.nix; then
        echo "Replace the placeholder public key in secrets/secrets.nix before rekeying secrets." >&2
        exit 1
      fi

      RULES="$repo_root/secrets/secrets.nix" agenix --rekey
    '';
  };
in {
  secret-edit = {
    type = "app";
    program = "${secretEdit}/bin/secret-edit";
  };

  secret-rekey = {
    type = "app";
    program = "${secretRekey}/bin/secret-rekey";
  };
}
