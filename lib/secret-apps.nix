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

      if [[ $# -lt 1 ]]; then
        echo "Usage: nix run .#secret-edit secrets/<name>.age" >&2
        exit 1
      fi

      full_path="''${!#}"
      if [[ "$full_path" != secrets/*.age ]]; then
        echo "Secret path must live under secrets/ and end with .age." >&2
        exit 1
      fi

      mkdir -p "$(dirname "$full_path")"
      export RULES="$repo_root/secrets/secrets.nix"

      if grep -q '"secrets/' "$RULES" 2>/dev/null; then
        cd "$repo_root"
        target_path="$full_path"
      else
        cd "$repo_root/secrets"
        target_path="''${full_path#secrets/}"
      fi

      # Collect all available identity keys in ~/.config/agenix/
      EXTRA_ARGS=()
      if [[ -d "$HOME/.config/agenix" ]]; then
        while IFS= read -r key_file; do
          EXTRA_ARGS+=("-i" "$key_file")
        done < <(find "$HOME/.config/agenix" -type f -name "*.age" -o -name "*.key" 2>/dev/null)
      fi

      exec agenix -e "$target_path" "''${EXTRA_ARGS[@]}"
    '';
  };

  secretRekey = pkgs.writeShellApplication {
    name = "secret-rekey";
    runtimeInputs = [agenixCli pkgs.git pkgs.gnugrep pkgs.findutils];
    text = ''
      set -euo pipefail

      repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
      export RULES="$repo_root/secrets/secrets.nix"

      if grep -q '"secrets/' "$RULES" 2>/dev/null; then
        cd "$repo_root"
      else
        cd "$repo_root/secrets"
      fi

      # Collect all available identity keys into an array
      EXTRA_OPTS=()
      if [[ -d "$HOME/.config/agenix" ]]; then
        while IFS= read -r key_file; do
          EXTRA_OPTS+=("-i" "$key_file")
        done < <(find "$HOME/.config/agenix" -type f \( -name "*.age" -o -name "*.key" -o -name "enterprise-d" \) 2>/dev/null)
      fi

      exec agenix --rekey "''${EXTRA_OPTS[@]}"
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
