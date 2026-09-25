#!/usr/bin/env bash
# A/B the text-to-image models under evaluation (2026-09-24) on the SAME
# library entries and the SAME seed, one model after another, logging the
# wall time of each. Output lands where generate.py always writes it:
# assets/flux/out/<chapter dir>/<ID>_<slug>_<model>_s<seed>.png
#
#   bash assets/flux/ab_models.sh                      # K-01, V-35, V-47 x 4 models
#   IDS=K-03,V-43 bash assets/flux/ab_models.sh        # other entries
#   MODELS="zimage qwen2512fast" bash assets/flux/ab_models.sh
#
# Needs ComfyUI running with the ComfyUI-GGUF node loaded (restart ComfyUI
# once after download_models.sh). Order is fastest first, so partial results
# are usable if you stop it; qwen2512 (50 steps) is the slow full-quality run.
set -uo pipefail
cd "$(dirname "$0")"
IDS="${IDS:-K-01,V-35,V-47}"
SEED="${SEED:-954159497}"
MODELS="${MODELS:-klein zimage qwen2512fast qwen2512}"
HOST="${COMFY_HOST:-http://127.0.0.1:8188}"

if ! curl -sf -m 5 "$HOST/system_stats" >/dev/null; then
  echo "ComfyUI is not answering at $HOST. Start Comfy Desktop first." >&2; exit 1
fi
if [[ "$MODELS" == *qwen* ]] && ! curl -sf -m 10 "$HOST/object_info/UnetLoaderGGUF" | grep -q UnetLoaderGGUF; then
  echo "ComfyUI has not loaded the GGUF node yet. Restart ComfyUI, then re-run." >&2; exit 1
fi

mkdir -p out
LOG="out/ab_$(date +%Y%m%d_%H%M).log"
echo "ids $IDS  seed $SEED  models: $MODELS  log $LOG"
for m in $MODELS; do
  echo "=== $m  start $(date +%T)" | tee -a "$LOG"
  t0=$(date +%s)
  python3 generate.py --ids "$IDS" --model "$m" --seed "$SEED" --timeout 3600 >> "$LOG" 2>&1
  rc=$?
  dt=$(( $(date +%s) - t0 ))
  n=$(echo "$IDS" | tr ',' '\n' | grep -c .)
  echo "=== $m  done in ${dt}s (~$(( dt / n ))s per image), exit $rc" | tee -a "$LOG"
done
echo; echo "saved:"; grep -c saved "$LOG" || true
echo "Done. Tell Claude; it builds the comparison sheet from out/."
