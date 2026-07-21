#!/usr/bin/env bash
# pull-image-model.sh — download an mflux image-gen model from hf-mirror to a local dir.
# Why not `ollama pull` / hf hub client: image models aren't in Ollama, and
# huggingface_hub rejects hf-mirror redirects (FileMetadataError). Plain curl works.
#
# Usage:
#   ./scripts/pull-image-model.sh Runpod/FLUX.2-klein-4B-mflux-4bit
#   ./scripts/pull-image-model.sh filipstrand/Z-Image-Turbo-mflux-4bit
set -euo pipefail

REPO="${1:?usage: pull-image-model.sh <hf-repo> [dest-root]}"
DEST_ROOT="${2:-$HOME/Downloads/image-gen-models}"
MIRROR="${HF_MIRROR:-https://hf-mirror.com}"
DEST="$DEST_ROOT/$(basename "$REPO")"
mkdir -p "$DEST"

echo "repo:   $REPO"
echo "dest:   $DEST"
echo "mirror: $MIRROR"

FILES=$(curl -sL -m 30 "$MIRROR/api/models/$REPO" \
  | python3 -c "import json,sys; print('\n'.join(s['rfilename'] for s in json.load(sys.stdin)['siblings'] if not s['rfilename'].startswith('.')))")

[ -n "$FILES" ] || { echo "ERROR: no files listed (repo wrong or mirror down)"; exit 1; }

for f in $FILES; do
  mkdir -p "$DEST/$(dirname "$f")"
  echo ">>> $f"
  curl -sL --retry 3 -C - -o "$DEST/$f" "$MIRROR/$REPO/resolve/main/$f"
done

echo "DONE"; du -sh "$DEST"
