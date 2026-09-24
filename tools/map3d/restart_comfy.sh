#!/bin/zsh
# Restart the local ComfyUI headless for gen_house_sources.py --restart.
# A Hunyuan3D prompt that runs the MPS pool dry keeps its allocations, so the
# shape and the paint of every house each start in a fresh server. The paths
# are Comfy Desktop's install on the owner's Mac (see the comfy-mcp-setup
# memory); COMFY_INSTALL / COMFY_SHARED / COMFY_MODEL_PATHS override them.
INSTALL=${COMFY_INSTALL:-$HOME/ComfyUI-Installs/GameDev}
SHARED=${COMFY_SHARED:-$HOME/ComfyUI-Shared}
MODELS=${COMFY_MODEL_PATHS:-$(ls "$HOME/Library/Application Support/Comfy Desktop/instance-model-paths/"*.yaml | head -1)}
LOG=${COMFY_LOG:-${TMPDIR:-/tmp}/comfyui_headless.log}
pkill -f "ComfyUI/main.py"; sleep 4
cd "$INSTALL"
PYTORCH_MPS_HIGH_WATERMARK_RATIO=2.0 nohup ComfyUI/.venv/bin/python3 -s ComfyUI/main.py \
  --enable-manager --extra-model-paths-config "$MODELS" \
  --input-directory "$SHARED/input" --output-directory "$SHARED/output" --port 8188 >> "$LOG" 2>&1 &
for i in $(seq 1 60); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' 127.0.0.1:8188/object_info/LoadImage)" = 200 ] && { echo up; exit 0; }
  sleep 3
done
echo down; exit 1
