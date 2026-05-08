#!/usr/bin/env bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

mapfile -t staged_files < <(git diff --cached --name-only --diff-filter=ACMR)

if [[ ${#staged_files[@]} -eq 0 ]]; then
  exit 0
fi

bad_paths=()
bad_contents=()
private_key_regex='BEGIN (OPENSSH|RSA|EC|DSA|PGP) PRIVATE KEY|AGE-SECRET-KEY-'
secret_content_regex='^(username|password)='

for path in "${staged_files[@]}"; do
  [[ -z "$path" ]] && continue

  if [[ "$path" == secrets/* && "$path" != "secrets/secrets.nix" && "$path" != *.age ]]; then
    bad_paths+=("$path")
    continue
  fi

  if [[ "$path" == tools/* ]]; then
    continue
  fi

  if ! git cat-file -e ":$path" 2>/dev/null; then
    continue
  fi

  if [[ "$path" == *.age ]]; then
    continue
  fi

  staged_content="$(git show ":$path")"

  if [[ "$path" == secrets/* ]] && grep -Eq "$secret_content_regex|$private_key_regex" <<<"$staged_content"; then
    bad_contents+=("$path")
    continue
  fi

  if grep -Eq "$private_key_regex" <<<"$staged_content"; then
    bad_contents+=("$path")
  fi
done

if [[ ${#bad_paths[@]} -gt 0 ]]; then
  echo "Refusing to commit non-.age files under secrets/:" >&2
  printf '  %s\n' "${bad_paths[@]}" >&2
  echo >&2
  echo "Create or rotate secrets with: nix run .#secret-edit -- secrets/<name>.age" >&2
  exit 1
fi

if [[ ${#bad_contents[@]} -gt 0 ]]; then
  echo "Refusing to commit likely plaintext secret material:" >&2
  printf '  %s\n' "${bad_contents[@]}" >&2
  echo >&2
  echo "Do not stage plaintext credentials or private keys. Use agenix and commit only .age files." >&2
  exit 1
fi
