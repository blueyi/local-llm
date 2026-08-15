#!/usr/bin/env bash
# =============================================================
# gen-image.sh — unified local text-to-image / image-edit wrapper
#                (reads config/image-models.manifest)
# =============================================================
# Usage:
#   ./scripts/gen-image.sh "a cute orange kitten"                    # generate with primary model
#   ./scripts/gen-image.sh --model z-image-turbo "portrait photo"    # pick a model
#   ./scripts/gen-image.sh --edit in.png "make the sky sunset" out.png  # edit (models with EDIT_CLI only)
#   ./scripts/gen-image.sh --size 1024x576 --steps 6 --seed 42 "..." # fine control
#
# Options:
#   --model <id>     model short name (see config/image-models.manifest, default: primary)
#   --size  WxH      resolution (default 768x768, use multiples of 16)
#   --steps N        sampling steps (default: from manifest)
#   --seed  N        random seed (default: random)
#   --out   PATH     output file (default ~/Pictures/gen/<timestamp>.png)
#   --edit  IN.png   image-to-image mode: modify IN.png according to the prompt
# =============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/common.sh"
MANIFEST="$ROOT/config/image-models.manifest"
WEIGHTS_ROOT="${IMAGE_MODELS_DIR:-$HOME/models/image-gen}"

MODEL_ID="" SIZE="768x768" STEPS="" SEED="" OUT="" EDIT_IN="" PROMPT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL_ID="$2"; shift 2 ;;
    --size)  SIZE="$2"; shift 2 ;;
    --steps) STEPS="$2"; shift 2 ;;
    --seed)  SEED="$2"; shift 2 ;;
    --out)   OUT="$2"; shift 2 ;;
    --edit)  EDIT_IN="$2"; shift 2 ;;
    -h|--help) grep -E '^#( |=)' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) if [[ -z "$PROMPT" ]]; then PROMPT="$1"; else OUT="${OUT:-$1}"; fi; shift ;;
  esac
done
[[ -n "$PROMPT" ]] || { echo "ERROR: missing prompt (see --help)"; exit 1; }

# ---- Resolve model row from manifest ----
pick_row() {
  # No --model -> primary row; otherwise match by MODEL_ID
  if [[ -z "$MODEL_ID" ]]; then
    grep -E '^primary\|' "$MANIFEST" | head -1
  else
    grep -E "^(primary|alt)\|$MODEL_ID\|" "$MANIFEST" | head -1
  fi
}
ROW="$(pick_row)"
[[ -n "$ROW" ]] || { echo "ERROR: model '$MODEL_ID' not found in manifest"; grep -E '^(primary|alt)\|' "$MANIFEST" | cut -d'|' -f1,2; exit 1; }
IFS='|' read -r ROLE ID HF_REPO GEN_CLI EDIT_CLI BASE_ARG DEF_STEPS <<< "$ROW"

MODEL_DIR="$WEIGHTS_ROOT/$(basename "$HF_REPO")"
[[ -d "$MODEL_DIR" ]] || { echo "ERROR: weights missing at $MODEL_DIR — run: lm pull-image $HF_REPO"; exit 1; }

STEPS="${STEPS:-$DEF_STEPS}"
WIDTH="${SIZE%x*}"; HEIGHT="${SIZE#*x}"
if [[ -z "$OUT" ]]; then
  mkdir -p "$HOME/Pictures/gen"
  OUT="$HOME/Pictures/gen/$(date +%Y%m%d-%H%M%S)-$ID.png"
fi

CMD=()
if [[ -n "$EDIT_IN" ]]; then
  [[ -n "$EDIT_CLI" ]] || { echo "ERROR: model $ID does not support editing (EDIT_CLI empty; choose a manifest model with edit support)"; exit 1; }
  [[ -f "$EDIT_IN" ]] || { echo "ERROR: input image not found: $EDIT_IN"; exit 1; }
  CMD=("$EDIT_CLI" --model "$MODEL_DIR" --image-path "$EDIT_IN")
else
  CMD=("$GEN_CLI" --model "$MODEL_DIR")
fi
[[ -n "$BASE_ARG" ]] && CMD+=(--base-model "$BASE_ARG")
CMD+=(--prompt "$PROMPT" --width "$WIDTH" --height "$HEIGHT" --steps "$STEPS" --output "$OUT")
[[ -n "$SEED" ]] && CMD+=(--seed "$SEED")

command -v "${CMD[0]}" >/dev/null 2>&1 || { echo "ERROR: mflux not installed — uv tool install mflux"; exit 1; }
echo ">>> [$ID] ${WIDTH}x${HEIGHT} steps=$STEPS ${EDIT_IN:+edit=$EDIT_IN }-> $OUT"
"${CMD[@]}"
echo "DONE: $OUT"
