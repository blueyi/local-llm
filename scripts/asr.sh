#!/usr/bin/env bash
# =============================================================
# asr.sh — speech-to-text via mlx-whisper (lm asr)
# =============================================================
# Usage:
#   lm asr <audio> [--model whisper-large-v3-turbo] [--lang zh|en|...] [-o outdir]
#   lm asr --help
#
# Reads config/speech-models.manifest. Weights under ~/models/speech/<basename>/.
# =============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/config/speech-models.manifest"
SPEECH_ROOT="${LLM_SPEECH_DIR:-$HOME/models/speech}"

MODEL_ID=""
AUDIO=""
LANG=""
OUTDIR=""

usage() { grep -E '^#( |=)' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --model) MODEL_ID="${2:-}"; shift 2 ;;
    --model=*) MODEL_ID="${1#--model=}"; shift ;;
    --lang) LANG="${2:-}"; shift 2 ;;
    --lang=*) LANG="${1#--lang=}"; shift ;;
    -o|--out) OUTDIR="${2:-}"; shift 2 ;;
    --out=*) OUTDIR="${1#--out=}"; shift ;;
    -*)
      echo "Unknown arg: $1"; usage; exit 1 ;;
    *)
      if [[ -z "$AUDIO" ]]; then AUDIO="$1"; else echo "Unexpected: $1"; exit 1; fi
      shift ;;
  esac
done

[[ -n "$AUDIO" ]] || { echo "usage: lm asr <audio> [--model id] [--lang zh]"; exit 1; }
[[ -f "$AUDIO" ]] || { echo "ERROR: audio not found: $AUDIO"; exit 1; }
command -v mlx_whisper >/dev/null 2>&1 || {
  echo "ERROR: mlx_whisper not installed. Run: uv tool install mlx-whisper"
  exit 1
}

# Resolve MODEL_ID -> HF basename path
if [[ -z "$MODEL_ID" ]]; then
  MODEL_ID="$(awk -F'|' '/^primary\|/{print $2; exit}' "$MANIFEST")"
fi
REPO="$(awk -F'|' -v id="$MODEL_ID" '$1!="retired" && $2==id {print $3; exit}' "$MANIFEST")"
[[ -n "$REPO" ]] || { echo "ERROR: unknown model id '$MODEL_ID' (see speech-models.manifest)"; exit 1; }
MODEL_PATH="$SPEECH_ROOT/$(basename "$REPO")"
[[ -f "$MODEL_PATH/weights.safetensors" || -f "$MODEL_PATH/config.json" ]] || {
  echo "ERROR: weights missing at $MODEL_PATH"
  echo "       run: lm pull-speech $REPO"
  exit 1
}

OUTDIR="${OUTDIR:-$(mktemp -d)/asr-out}"
mkdir -p "$OUTDIR"

ARGS=(mlx_whisper "$AUDIO" --model "$MODEL_PATH" -o "$OUTDIR" --output-format txt)
[[ -n "$LANG" ]] && ARGS+=(--language "$LANG")

echo "ASR model: $MODEL_ID  ($MODEL_PATH)"
echo "Audio:     $AUDIO"
"${ARGS[@]}"
echo
echo "Output dir: $OUTDIR"
# Print transcript text files
find "$OUTDIR" -name '*.txt' -print -exec cat {} \;
