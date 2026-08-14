#!/usr/bin/env bash
# =============================================================
# pull-gguf.sh - download manifest HF GGUF (+ mmproj) into ~/models/gguf
# =============================================================
# For LM Studio / manual import. Does NOT ollama pull or ollama create.
# (~/.lmstudio/models/llm-gguf should symlink here - run link script after.)
#
# Usage:
#   lm pull-gguf              # all tiers that have HF_GGUF_URL
#   lm pull-gguf main deep    # selected tiers
#   lm pull-gguf --link       # also refresh LM Studio symlink
# =============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/config/models.manifest"
GGUF_DIR="${LLM_GGUF_DIR:-$HOME/models/gguf}"
HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"
DO_LINK=0
TIERS=()

for arg in "$@"; do
  case "$arg" in
    --link) DO_LINK=1 ;;
    -h|--help) grep -E '^#( |=)' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    main|deep|fast|embed|chat|reason|rerank) TIERS+=("$arg") ;;
    *) echo "Unknown arg: $arg"; exit 1 ;;
  esac
done

log()  { printf '\033[1;36m>>> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m OK %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!!! %s\033[0m\n' "$*"; }
err()  { printf '\033[1;31mERR %s\033[0m\n' "$*"; }

download_gguf() {
  # $1 url  $2 optional local filename override
  # echoes local path; resumable against final CDN URL
  local url="$1" fname_override="${2:-}" mirrored fname dest final attempt
  mirrored="${url/https:\/\/huggingface.co/$HF_ENDPOINT}"
  fname="${fname_override:-$(basename "$url")}"
  dest="$GGUF_DIR/$fname"
  mkdir -p "$GGUF_DIR"
  log "Downloading $fname  <- $HF_ENDPOINT" >&2
  for attempt in 1 2 3 4 5; do
    final="$(curl -sIL -o /dev/null -w '%{url_effective}' -m 30 "$mirrored" || true)"
    [[ -z "$final" ]] && { warn "resolve failed (attempt $attempt)" >&2; sleep 3; continue; }
    local remote_size local_size
    remote_size="$(curl -sI -m 30 "$final" | tr -d '\r' | awk 'tolower($1)=="content-length:"{print $2}' | tail -1)"
    local_size="$(stat -f%z "$dest" 2>/dev/null || echo 0)"
    if [[ -n "$remote_size" && "$local_size" == "$remote_size" ]]; then
      ok "already complete: $dest" >&2
      echo "$dest"
      return 0
    fi
    local range_code
    range_code="$(curl -s -o /dev/null -w '%{http_code}' -r 0-0 -m 30 "$final" || echo 000)"
    if [[ "$range_code" == "206" ]]; then
      if curl -f -C - --retry 3 --retry-delay 3 -o "$dest" "$final" >&2; then
        echo "$dest"; return 0
      fi
      warn "interrupted (attempt $attempt); keeping partial $dest" >&2
    else
      warn "no Range (HTTP $range_code); full re-download" >&2
      if curl -f -L --retry 3 --retry-delay 3 -o "$dest" "$final" >&2; then
        echo "$dest"; return 0
      fi
    fi
    sleep 3
  done
  err "download failed: $mirrored" >&2
  return 1
}

[[ -f "$MANIFEST" ]] || { err "manifest missing: $MANIFEST"; exit 1; }
mkdir -p "$GGUF_DIR"

log "GGUF dir: $GGUF_DIR  (mirror: $HF_ENDPOINT)"
COUNT=0
SKIP=0
while IFS='|' read -r tier tag ctx gguf_url mmproj_url; do
  [[ "$tier" =~ ^#|^$|^retired$ ]] && continue
  if [[ ${#TIERS[@]} -gt 0 ]]; then
    keep=0
    for t in "${TIERS[@]}"; do [[ "$t" == "$tier" ]] && keep=1; done
    [[ "$keep" -eq 1 ]] || continue
  fi
  gguf_url="$(echo "${gguf_url:-}" | xargs)"
  mmproj_url="$(echo "${mmproj_url:-}" | xargs)"
  if [[ -z "$gguf_url" ]]; then
    warn "[$tier] $tag has no HF_GGUF_URL - skip (Ollama-only / community)"
    SKIP=$((SKIP + 1))
    continue
  fi
  log "[$tier] $tag"
  gguf_path="$(download_gguf "$gguf_url")"
  # mmproj files are often all named mmproj-F16.gguf - prefix with GGUF stem
  if [[ -n "$mmproj_url" ]]; then
    stem="$(basename "$gguf_path" .gguf)"
    download_gguf "$mmproj_url" "${stem}.mmproj-F16.gguf" >/dev/null || true
  fi
  COUNT=$((COUNT + 1))
done < "$MANIFEST"

echo
ok "Downloaded GGUF sets: $COUNT  (skipped no-URL: $SKIP)"
du -sh "$GGUF_DIR"/* 2>/dev/null | sort -h || du -sh "$GGUF_DIR"

if [[ "$DO_LINK" -eq 1 ]] || [[ -d "$HOME/.lmstudio" ]]; then
  log "Refreshing LM Studio symlink"
  "$ROOT/scripts/link-lmstudio-models.sh" "$GGUF_DIR" || true
fi

echo
ok "In LM Studio: My Models → look under llm-gguf / ~/models/gguf"
echo "   Tip: load mmproj alongside VL GGUFs when you need vision."
