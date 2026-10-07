#!/bin/bash
# Cloud sessions only: install a headless Godot so ./run_tests.sh runs there.
# Local machines use their own Godot (run_tests.sh defaults to the macOS app).
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

GODOT_VERSION="4.7-stable"
GODOT_DIR="$HOME/.local/godot/$GODOT_VERSION"
GODOT_BIN="$GODOT_DIR/Godot_v${GODOT_VERSION}_linux.x86_64"

if [ ! -x "$GODOT_BIN" ]; then
  mkdir -p "$GODOT_DIR"
  zip="$GODOT_DIR/godot.zip"
  url="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip"
  for delay in 2 4 8 16 0; do
    if curl -fsSL "$url" -o "$zip"; then break; fi
    [ "$delay" = "0" ] && { echo "Godot download failed" >&2; exit 1; }
    sleep "$delay"
  done
  python3 -c "import sys,zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$zip" "$GODOT_DIR"
  rm -f "$zip"
  chmod +x "$GODOT_BIN"
fi

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export GODOT=\"$GODOT_BIN\"" >> "$CLAUDE_ENV_FILE"
fi

# One import pass so .godot/ exists (the first pass prints font/theme errors).
cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"
if [ ! -d .godot/imported ]; then
  "$GODOT_BIN" --headless --path . --import > /dev/null 2>&1 || true
fi
