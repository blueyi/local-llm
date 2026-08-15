#!/usr/bin/env bash
# Download mlx-audio TTS weights from the TTS manifest or an explicit repo.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/common.sh"
source "$ROOT/scripts/lib/hf_download.sh"
MANIFEST="$ROOT/config/tts-models.manifest"
DEST_ROOT="${LLM_TTS_DIR:-$HOME/models/tts}"
REPO="${1:-$(manifest_primary_value "$MANIFEST" 3)}"
[[ -n "$REPO" ]] || { err "no repo (pass arg or set primary in tts-models.manifest)"; exit 1; }
DEST="$DEST_ROOT/$(basename "$REPO")"
echo "repo:   $REPO"
echo "dest:   $DEST"
echo "mirror: $HF_MIRROR"
hf_download_repo "$REPO" "$DEST_ROOT" 1 >/dev/null
echo "DONE"; du -sh "$DEST"
