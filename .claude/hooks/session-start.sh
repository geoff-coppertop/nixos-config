#!/bin/bash
set -euo pipefail

# Only run in remote (web) environments
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

TOOLS_DIR="$HOME/.local/bin"
mkdir -p "$TOOLS_DIR"

# alejandra 4.0.0 — Nix formatter (the linter that previously required a full Nix install)
if ! command -v alejandra &>/dev/null; then
  echo "Installing alejandra 4.0.0..."
  curl -LSso "$TOOLS_DIR/alejandra" \
    "https://github.com/kamadorueda/alejandra/releases/download/4.0.0/alejandra-x86_64-unknown-linux-musl"
  chmod +x "$TOOLS_DIR/alejandra"
fi

# markdownlint-cli — Markdown linter
if ! command -v markdownlint &>/dev/null; then
  echo "Installing markdownlint-cli..."
  npm install -g markdownlint-cli --silent
fi

# Persist PATH for the session
echo "export PATH=\"$TOOLS_DIR:/opt/node22/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"

echo "Linter tools ready: alejandra $(alejandra --version 2>/dev/null | head -1), markdownlint $(markdownlint --version 2>/dev/null)"
