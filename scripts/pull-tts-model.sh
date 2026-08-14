#!/usr/bin/env bash
# =============================================================
# pull-tts-model.sh — download mlx-audio TTS weights via hf-mirror
# =============================================================
# Same pattern as pull-speech-model.sh. Skips samples/ (demo wavs).
#
# Usage:
#   lm pull-tts                              # primary from tts-models.manifest
#   lm pull-tts mlx-community/Kokoro-82M-bf16
# =============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/config/tts-models.manifest"
DEST_ROOT="${LLM_TTS_DIR:-$HOME/models/tts}"
MIRROR="${HF_MIRROR:-https://hf-mirror.com}"

REPO="${1:-}"
if [[ -z "$REPO" ]]; then
  REPO="$(awk -F'|' '/^primary\|/{print $3; exit}' "$MANIFEST")"
fi
[[ -n "$REPO" ]] || { echo "ERROR: no repo (pass arg or set primary in tts-models.manifest)"; exit 1; }

DEST="$DEST_ROOT/$(basename "$REPO")"
mkdir -p "$DEST"

echo "repo:   $REPO"
echo "dest:   $DEST"
echo "mirror: $MIRROR"

FILES=$(curl -sL -m 30 "$MIRROR/api/models/$REPO" \
  | python3 -c "
import json,sys
files=[]
for s in json.load(sys.stdin).get('siblings') or []:
    f=s['rfilename']
    if f.startswith('.') or f.startswith('samples/'):
        continue
    files.append(f)
print('\n'.join(files))
")
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
