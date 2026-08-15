#!/usr/bin/env bash
# Unified Hugging Face model downloader for image, speech and TTS manifests.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/common.sh"
source "$ROOT/scripts/lib/hf_download.sh"

KIND=""
REPO=""
DEST_ROOT=""

usage() {
  cat <<'EOF'
Usage: pull-hf-model.sh --kind image|speech|tts [repo] [dest-root]
When repo is omitted, the primary repo is read from the corresponding manifest.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kind) KIND="${2:-}"; shift 2 ;;
    --kind=*) KIND="${1#--kind=}"; shift ;;
    --help|-h) usage; exit 0 ;;
    --) shift; break ;;
    -*) err "unknown argument: $1"; usage >&2; exit 1 ;;
    *)
      if [[ -z "$REPO" ]]; then REPO="$1"
      elif [[ -z "$DEST_ROOT" ]]; then DEST_ROOT="$1"
      else err "unexpected argument: $1"; exit 1
      fi
      shift
      ;;
  esac
done

case "$KIND" in
  image)
    MANIFEST="$ROOT/config/image-models.manifest"
    DEST_ROOT="${DEST_ROOT:-${IMAGE_MODELS_DIR:-$HOME/models/image-gen}}"
    [[ -n "$REPO" ]] || { err "usage: lm pull-image <hf-repo>"; exit 1; }
    ;;
  speech)
    MANIFEST="$ROOT/config/speech-models.manifest"
    DEST_ROOT="${DEST_ROOT:-${LLM_SPEECH_DIR:-$HOME/models/speech}}"
    ;;
  tts)
    MANIFEST="$ROOT/config/tts-models.manifest"
    DEST_ROOT="${DEST_ROOT:-${LLM_TTS_DIR:-$HOME/models/tts}}"
    ;;
  *) err "--kind must be image, speech or tts"; usage >&2; exit 1 ;;
esac

[[ -f "$MANIFEST" ]] || { err "manifest missing: $MANIFEST"; exit 1; }
REPO="${REPO:-$(manifest_primary_value "$MANIFEST" 3)}"
[[ -n "$REPO" ]] || { err "no primary repo in $MANIFEST"; exit 1; }

DEST="$DEST_ROOT/$(basename "$REPO")"
echo "kind:   $KIND"
echo "repo:   $REPO"
echo "dest:   $DEST"
echo "mirror: $HF_MIRROR"
if [[ "$KIND" == "tts" ]]; then
  hf_download_repo "$REPO" "$DEST_ROOT" 1 >/dev/null
else
  hf_download_repo "$REPO" "$DEST_ROOT" 0 >/dev/null
fi
echo "DONE"; du -sh "$DEST"
