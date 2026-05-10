{
  pkgs,
  agenixCli,
}: let
  secretEdit = pkgs.writeShellApplication {
    name = "secret-edit";
    runtimeInputs = [agenixCli pkgs.coreutils pkgs.git pkgs.gnugrep];
    text = ''
      set -euo pipefail

      repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

      # Validate we have at least one argument
      if [[ $# -lt 1 ]]; then
        echo "Usage: nix run .#secret-edit -- [options] secrets/<name>.age" >&2
        exit 1
      fi

      # The actual file on disk needs the 'secrets/' prefix
      full_path="''${!#}"

      # The key inside secrets.nix does NOT have the 'secrets/' prefix
      # We strip 'secrets/' from the start of the string
      relative_key="''${full_path#secrets/}"

      if [[ "$full_path" != secrets/*.age ]]; then
        echo "Secret path must live under secrets/ and end with .age." >&2
        exit 1
      fi

      mkdir -p "$(dirname "$full_path")"

      # We CD into the secrets directory so agenix matches the relative_key perfectly
      cd "$repo_root/secrets"

      # We use "$@" so flags like -i still work, but replace the last arg with our cleaned key
      set -- "''${@:1:$#-1}" "$relative_key"

      RULES="$PWD/secrets.nix" exec agenix -e "$@"
    '';
  };

  secretRekey = pkgs.writeShellApplication {
    name = "secret-rekey";
    runtimeInputs = [agenixCli pkgs.git pkgs.gnugrep];
    text = ''
      set -euo pipefail

      repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
      cd "$repo_root/secrets"

      # Check for your specific key path and auto-inject it if it exists
      EXTRA_OPTS=()
      if [[ -f "$HOME/.config/agenix/nixos-config.age" ]]; then
        EXTRA_OPTS+=("-i" "$HOME/.config/agenix/nixos-config.age")
      fi

      RULES="$PWD/secrets.nix" exec agenix --rekey "''${EXTRA_OPTS[@]}" "$@"
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
