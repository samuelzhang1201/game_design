#!/usr/bin/env bash
# Download the open-weight text-to-image models behind generate.py's
# zimage / qwen2512 / qwen2512fast presets into the folder Comfy Desktop reads
# models from (~/ComfyUI-Shared/models), and install the Python deps of the
# ComfyUI-GGUF node (installed into custom_nodes/ComfyUI-GGUF on 2026-09-24).
#
#   bash assets/flux/download_models.sh           # everything, ~47 GB
#   bash assets/flux/download_models.sh zimage    # Z-Image Turbo only, ~12 GB
#   bash assets/flux/download_models.sh qwen      # Qwen-Image-2512 stack only, ~35 GB
#   bash assets/flux/download_models.sh qwenedit  # Qwen-Image-Edit-2511 (+ the qwen stack's encoder/VAE), ~18 GB more
#
# Resumable: re-run after an interruption and curl continues each .part file.
# Every model here is Apache 2.0 (checked 2026-09-24; see the Claude project doc
# claude/t2i-model-evaluation-2026-09.md). Restart ComfyUI afterwards so it
# loads the GGUF node. Runs on macOS (uses BSD stat).
set -euo pipefail
MODELS="${COMFY_MODELS:-$HOME/ComfyUI-Shared/models}"
# Comfy Desktop runs ComfyUI from ComfyUI/.venv (created by uv from
# standalone-env, include-system-site-packages = false), so node deps must go
# into THAT venv. It has no pip, so uv installs into it. (2026-09-24 fix: the
# first version installed into standalone-env, which ComfyUI never imports.)
PY="${COMFY_PY:-$HOME/ComfyUI-Installs/GameDev/ComfyUI/.venv/bin/python}"
UV="${COMFY_UV:-$HOME/ComfyUI-Installs/GameDev/standalone-env/bin/uv}"
WHAT="${1:-all}"
HF=https://huggingface.co

fetch() {  # <models subdir> <file name> <url>
  local dir="$MODELS/$1" out="$MODELS/$1/$2" url="$3"
  mkdir -p "$dir"
  if [[ -f "$out" ]]; then echo "have  $1/$2"; return; fi
  echo "get   $1/$2"
  curl -L --fail --retry 5 --retry-delay 5 -C - -o "$out.part" "$url"
  local want got
  want=$(curl -sIL "$url" | awk 'tolower($1)=="content-length:"{v=$2} END{gsub("\r","",v); print v}')
  got=$(stat -f%z "$out.part")
  if [[ -n "$want" && "$want" != "$got" ]]; then
    echo "size mismatch for $2: got $got, server says $want. Re-run to resume." >&2; exit 1
  fi
  mv "$out.part" "$out"; echo "ok    $1/$2 ($got bytes)"
}

if [[ "$WHAT" == all || "$WHAT" == zimage ]]; then
  # Z-Image Turbo (Tongyi-MAI): the model, its text encoder and its VAE.
  # fetch skips files that already exist.
  fetch diffusion_models z_image_turbo_bf16.safetensors \
    "$HF/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors"
  fetch text_encoders qwen_3_4b.safetensors \
    "$HF/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors"
  fetch vae ae.safetensors \
    "$HF/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors"
fi

if [[ "$WHAT" == all || "$WHAT" == qwen || "$WHAT" == qwenedit ]]; then
  # Qwen-Image-2512 as Q6_K GGUF: on MPS ComfyUI upcasts fp8 to 16-bit, so the
  # fp8 file would sit at ~41 GB in memory; the GGUF stays ~17 GB.
  fetch diffusion_models qwen-image-2512-Q6_K.gguf \
    "$HF/unsloth/Qwen-Image-2512-GGUF/resolve/main/qwen-image-2512-Q6_K.gguf"
  # bf16 encoder: the fp8 one is smaller to download but is upcast on MPS anyway.
  fetch text_encoders qwen_2.5_vl_7b.safetensors \
    "$HF/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/text_encoders/qwen_2.5_vl_7b.safetensors"
  fetch vae qwen_image_vae.safetensors \
    "$HF/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/vae/qwen_image_vae.safetensors"
  fetch loras Qwen-Image-2512-Lightning-8steps-V1.0-bf16.safetensors \
    "$HF/lightx2v/Qwen-Image-2512-Lightning/resolve/main/Qwen-Image-2512-Lightning-8steps-V1.0-bf16.safetensors"
  echo "deps  gguf + protobuf into ComfyUI's venv ($PY)"
  if "$PY" -m pip --version >/dev/null 2>&1; then
    "$PY" -m pip install --quiet "gguf>=0.13.0" protobuf
  else
    "$UV" pip install --python "$PY" "gguf>=0.13.0" protobuf
  fi
  "$PY" -c "import gguf, google.protobuf; print('ok    gguf', gguf.__file__)"
fi

if [[ "$WHAT" == all || "$WHAT" == qwenedit ]]; then
  # Qwen-Image-Edit-2511 (Apache 2.0, checked 2026-10-10 on the Qwen, unsloth and
  # lightx2v model cards): image editing for generate.py's qwenedit presets. It
  # shares the qwen stack's text encoder and VAE (fetched above). Q6_K GGUF for
  # the same MPS reason as 2512.
  fetch diffusion_models qwen-image-edit-2511-Q6_K.gguf \
    "$HF/unsloth/Qwen-Image-Edit-2511-GGUF/resolve/main/qwen-image-edit-2511-Q6_K.gguf"
  fetch loras Qwen-Image-Edit-2511-Lightning-8steps-V1.0-bf16.safetensors \
    "$HF/lightx2v/Qwen-Image-Edit-2511-Lightning/resolve/main/Qwen-Image-Edit-2511-Lightning-8steps-V1.0-bf16.safetensors"
fi

echo
echo "Done. Restart ComfyUI (Comfy Desktop), then try:"
echo "  python3 assets/flux/generate.py --ids K-01 --model zimage"
echo "  python3 assets/flux/generate.py --ids K-01 --model qwen2512fast"
