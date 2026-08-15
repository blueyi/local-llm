#!/usr/bin/env bash
# Download an mflux image-gen model from the configured HF mirror.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/common.sh"
source "$ROOT/scripts/lib/hf_download.sh"

REPO="${1:?usage: pull-image-model.sh <hf-repo> [dest-root]}"
DEST_ROOT="${2:-$HOME/models/image-gen}"
DEST="$DEST_ROOT/$(basename "$REPO")"
echo "repo:   $REPO"
echo "dest:   $DEST"
echo "mirror: $HF_MIRROR"
hf_download_repo "$REPO" "$DEST_ROOT" 0 >/dev/null
echo "DONE"; du -sh "$DEST"
