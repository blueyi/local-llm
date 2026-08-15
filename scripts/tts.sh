#!/usr/bin/env bash
# =============================================================
# tts.sh — text-to-speech via mlx-audio (lm tts)
# =============================================================
# Usage:
#   lm tts "Hello world"                              # primary Kokoro
#   lm tts "你好，世界" --model qwen3-tts-1.7b         # quality Qwen3-TTS
#   lm tts "I'm so happy!" --model qwen3-tts-1.7b --voice Vivian \
#        --lang Chinese --instruct "Very happy and excited."
#   lm tts "text" [--model id] [--voice ...] [--lang ...] [-o outdir] [--play]
#   lm tts --help
#
# Reads config/tts-models.manifest. Weights under ~/models/tts/<basename>/.
# =============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/common.sh"
MANIFEST="$ROOT/config/tts-models.manifest"
TTS_ROOT="${LLM_TTS_DIR:-$HOME/models/tts}"

MODEL_ID=""
TEXT=""
VOICE=""
LANG=""
INSTRUCT=""
OUTDIR=""
PLAY=0
SPEED=""
FILE_PREFIX="tts"

usage() { grep -E '^#( |=)' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --model) MODEL_ID="${2:-}"; shift 2 ;;
    --model=*) MODEL_ID="${1#--model=}"; shift ;;
    --voice) VOICE="${2:-}"; shift 2 ;;
    --voice=*) VOICE="${1#--voice=}"; shift ;;
    --lang) LANG="${2:-}"; shift 2 ;;
    --lang=*) LANG="${1#--lang=}"; shift ;;
    --instruct) INSTRUCT="${2:-}"; shift 2 ;;
    --instruct=*) INSTRUCT="${1#--instruct=}"; shift ;;
    --speed) SPEED="${2:-}"; shift 2 ;;
    --speed=*) SPEED="${1#--speed=}"; shift ;;
    -o|--out) OUTDIR="${2:-}"; shift 2 ;;
    --out=*) OUTDIR="${1#--out=}"; shift ;;
    --prefix) FILE_PREFIX="${2:-}"; shift 2 ;;
    --play) PLAY=1; shift ;;
    -*)
      echo "Unknown arg: $1"; usage; exit 1 ;;
    *)
      if [[ -z "$TEXT" ]]; then TEXT="$1"; else echo "Unexpected: $1"; exit 1; fi
      shift ;;
  esac
done

[[ -n "$TEXT" ]] || {
  echo "usage: lm tts \"text\" [--model kokoro-82m|qwen3-tts-1.7b] [--voice ...] [--lang ...]"
  exit 1
}
command -v mlx_audio.tts.generate >/dev/null 2>&1 || {
  echo "ERROR: mlx_audio.tts.generate not installed."
  echo "       Run: uv tool install mlx-audio --with 'misaki[en]' --with 'misaki[zh]'"
  exit 1
}

if [[ -z "$MODEL_ID" ]]; then
  MODEL_ID="$(manifest_primary_value "$MANIFEST" 2)"
fi
REPO="$(manifest_value "$MANIFEST" "$MODEL_ID" 3)"
DEFAULT_VOICE="$(manifest_value "$MANIFEST" "$MODEL_ID" 5)"
[[ -n "$REPO" ]] || { echo "ERROR: unknown model id '$MODEL_ID' (see tts-models.manifest)"; exit 1; }
MODEL_PATH="$TTS_ROOT/$(basename "$REPO")"
[[ -f "$MODEL_PATH/config.json" ]] || {
  echo "ERROR: weights missing at $MODEL_PATH"
  echo "       run: lm pull-tts $REPO"
  exit 1
}
if [[ ! -f "$MODEL_PATH/kokoro-v1_0.safetensors" && ! -f "$MODEL_PATH/model.safetensors" ]]; then
  echo "ERROR: weight file missing under $MODEL_PATH (expect kokoro-v1_0.safetensors or model.safetensors)"
  echo "       run: lm pull-tts $REPO"
  exit 1
fi

VOICE="${VOICE:-$DEFAULT_VOICE}"
HAS_CJK=0
if printf '%s' "$TEXT" | python3 -c "import sys; t=sys.stdin.read(); sys.exit(0 if any('\u4e00'<=c<='\u9fff' for c in t) else 1)"; then
  HAS_CJK=1
fi

# Family-specific language / voice defaults
case "$MODEL_ID" in
  qwen3-tts*|*-qwen3*)
    if [[ -z "$LANG" ]]; then
      if [[ "$HAS_CJK" -eq 1 ]]; then LANG=Chinese; else LANG=English; fi
    fi
    # Map short codes if user passed Kokoro-style langs
    case "$LANG" in
      z|zh|zh-cn|cmn) LANG=Chinese ;;
      a|en|en-us) LANG=English ;;
    esac
    if [[ "$HAS_CJK" -eq 1 && "$VOICE" == "$DEFAULT_VOICE" ]]; then
      VOICE=Vivian
    fi
    ;;
  *)
    if [[ -z "$LANG" && "$HAS_CJK" -eq 1 ]]; then
      LANG=z
      [[ "$VOICE" == "$DEFAULT_VOICE" ]] && VOICE=zf_xiaoxiao
    fi
    ;;
esac

OUTDIR="${OUTDIR:-$(mktemp -d)/tts-out}"
mkdir -p "$OUTDIR"

ARGS=(
  mlx_audio.tts.generate
  --model "$MODEL_PATH"
  --text "$TEXT"
  --voice "$VOICE"
  --output_path "$OUTDIR"
  --file_prefix "$FILE_PREFIX"
  --join_audio
)
[[ -n "$LANG" ]] && ARGS+=(--lang_code "$LANG")
[[ -n "$INSTRUCT" ]] && ARGS+=(--instruct "$INSTRUCT")
[[ -n "$SPEED" ]] && ARGS+=(--speed "$SPEED")
[[ "$PLAY" -eq 1 ]] && ARGS+=(--play)

echo "TTS model: $MODEL_ID  ($MODEL_PATH)"
echo "Voice:     $VOICE${LANG:+  lang=$LANG}${INSTRUCT:+  instruct=$INSTRUCT}"
echo "Text:      $TEXT"
"${ARGS[@]}"
echo
echo "Output dir: $OUTDIR"
ls -lh "$OUTDIR"/*."${AUDIO_FORMAT:-wav}" 2>/dev/null || ls -lh "$OUTDIR" 2>/dev/null || true
