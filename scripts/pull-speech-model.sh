#!/usr/bin/env bash
# =============================================================
# pull-speech-model.sh — download mlx-whisper weights via hf-mirror
# =============================================================
# Same rationale as pull-image-model.sh: huggingface_hub + mirror is flaky;
# plain curl against hf-mirror (then CDN) works with resume.
#
# Usage:
#   lm pull-speech                         # primary from speech-models.manifest
#   lm pull-speech mlx-community/whisper-large-v3-turbo
# =============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/config/speech-models.manifest"
DEST_ROOT="${LLM_SPEECH_DIR:-$HOME/models/speech}"
MIRROR="${HF_MIRROR:-https://hf-mirror.com}"

REPO="${1:-}"
if [[ -z "$REPO" ]]; then
  REPO="$(awk -F'|' '/^primary\|/{print $3; exit}' "$MANIFEST")"
fi
[[ -n "$REPO" ]] || { echo "ERROR: no repo (pass arg or set primary in speech-models.manifest)"; exit 1; }

DEST="$DEST_ROOT/$(basename "$REPO")"
mkdir -p "$DEST"

echo "repo:   $REPO"
echo "dest:   $DEST"
echo "mirror: $MIRROR"

FILES=$(curl -sL -m 30 "$MIRROR/api/models/$REPO" \
  | python3 -c "import json,sys; print('\n'.join(s['rfilename'] for s in json.load(sys.stdin)['siblings'] if not s['rfilename'].startswith('.')))")
[[ -n "$FILES" ]] || { echo "ERROR: no files listed (repo wrong or mirror down)"; exit 1; }

download_one() {
  local f="$1" mirrored final range_code remote_size local_size
  mirrored="$MIRROR/$REPO/resolve/main/$f"
  mkdir -p "$DEST/$(dirname "$f")"
  echo ">>> $f"
  for attempt in 1 2 3 4 5; do
    final="$(curl -sIL -o /dev/null -w '%{url_effective}' -m 30 "$mirrored" || true)"
    [[ -n "$final" ]] || { sleep 2; continue; }
    remote_size="$(curl -sI -m 30 "$final" | tr -d '\r' | awk 'tolower($1)=="content-length:"{print $2}' | tail -1)"
    local_size="$(stat -f%z "$DEST/$f" 2>/dev/null || echo 0)"
    if [[ -n "$remote_size" && "$local_size" == "$remote_size" ]]; then
      echo "    already complete ($local_size bytes)"; return 0
    fi
    range_code="$(curl -s -o /dev/null -w '%{http_code}' -r 0-0 -m 30 "$final" || echo 000)"
    if [[ "$range_code" == "206" ]]; then
      curl -f -C - --retry 3 --retry-delay 2 -o "$DEST/$f" "$final" && return 0
    else
      curl -f -L --retry 3 --retry-delay 2 -o "$DEST/$f" "$final" && return 0
    fi
    sleep 2
  done
  echo "ERROR: failed to download $f"; return 1
}

while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  download_one "$f"
done <<< "$FILES"

echo "DONE"; du -sh "$DEST"
