#!/usr/bin/env bash
# Build the 3D military units and photograph them. See README.md.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
SHOTS="${SHOTS:-$ROOT/assets/3D/units/shots}"
mkdir -p "$SHOTS"
cd "$ROOT"
"$BLENDER" -b --factory-startup --python tools/units3d/make_units.py -- "$@"
"$BLENDER" -b --factory-startup --python tools/units3d/shoot_units.py -- "$SHOTS" "$@"
echo "units3d: shots in $SHOTS"
