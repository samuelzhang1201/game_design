#!/bin/sh
# Build one pack's 3D map, the whole chain (spec 2026-09-20 §3):
#   tools/map3d/build_pack.sh [--map ID]      (default: data/maps.csv is_default)
# export_manor_land -> bake_world.py -> build_world.gd, into the pack's
# maps.csv map3d_dir (default assets/map3d/<id>), manifest.json last.
# The textures (pack_textures.py, Blender) are shared by every pack and built
# once — see README.
set -e
cd "$(dirname "$0")/../.."
MAP=""
while [ $# -gt 0 ]; do
  case "$1" in
    --map) MAP="$2"; shift 2 ;;
    *) echo "usage: $0 [--map ID]" >&2; exit 2 ;;
  esac
done
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
# the gdai plugin's runtime server must not collide with an open editor's 3571
export GDAI_MCP_SERVER_PORT=3999
if [ -n "$MAP" ]; then
  "$GODOT" --headless --path . -s tools/map3d/export_manor_land.gd -- --map "$MAP"
  python3 tools/map3d/bake_world.py --map "$MAP"
  "$GODOT" --headless --path . -s tools/map3d/build_world.gd -- --map "$MAP"
else
  "$GODOT" --headless --path . -s tools/map3d/export_manor_land.gd
  python3 tools/map3d/bake_world.py
  "$GODOT" --headless --path . -s tools/map3d/build_world.gd
fi
echo "build_pack: done — see the manifest line above (<map3d_dir>/manifest.json)"
