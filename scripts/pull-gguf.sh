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
#   lm pull-gguf --link-only  # refresh symlink without downloading
#
# Incomplete / interrupted downloads resume automatically (curl -C -).
# Large files use HTTP/1.1 to avoid CDN HTTP/2 stream resets (curl 92).
# =============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/common.sh"
MANIFEST="$ROOT/config/models.manifest"
GGUF_DIR="${LLM_GGUF_DIR:-$HOME/models/gguf}"
HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"
DO_LINK=0
LINK_ONLY=0
TIERS=()

link_lmstudio_models() {
  local src="$1" dest target
  local candidates=(
    "$HOME/.lmstudio/models"
    "$HOME/.cache/lm-studio/models"
    "$HOME/Library/Application Support/LM Studio/models"
  )
  for dest in "${candidates[@]}"; do
    [[ -d "$dest" ]] && break
  done
  if [[ ! -d "${dest:-}" ]]; then
    dest="$HOME/.lmstudio/models"
    mkdir -p "$dest"
    echo "Created $dest"
  fi
  [[ -d "$src" ]] || { err "source not found: $src"; return 1; }
  target="$dest/llm-gguf"
  mkdir -p "$(dirname "$target")"
  ln -sfn "$src" "$target"
  ok "Linked: $target -> $src"
  ls -la "$target" | head -30
}

for arg in "$@"; do
  case "$arg" in
    --link) DO_LINK=1 ;;
    --link-only) DO_LINK=1; LINK_ONLY=1 ;;
    -h|--help) grep -E '^#( |=)' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)
      if is_known_llm_tier "$arg"; then
        TIERS+=("$arg")
      else
        echo "Unknown arg: $arg"; exit 1
      fi
      ;;
  esac
done

download_gguf() {
  # $1 url  $2 optional local filename override
  # echoes local path; resumable against final CDN URL
  #
  # Pitfalls:
  #   - HTTP/2 stream reset (curl 92) → use --http1.1
  #   - Truncated body (curl 18) → resume with -C -
  #   - CDN DNS flap / expired signed URL (curl 6) → do NOT let curl
  #     --retry hammer the same host; re-resolve via hf-mirror each attempt
  local url="$1" fname_override="${2:-}" mirrored fname dest final attempt
  local remote_size local_size range_code curl_rc sleep_s host
  mirrored="${url/https:\/\/huggingface.co/$HF_ENDPOINT}"
  fname="${fname_override:-$(basename "$url")}"
  dest="$GGUF_DIR/$fname"
  mkdir -p "$GGUF_DIR"
  log "Downloading $fname  <- $HF_ENDPOINT" >&2
  for attempt in $(seq 1 20); do
    # Always re-resolve: signed CDN URLs expire; DNS may recover on new hop
    final="$(curl -sIL --http1.1 --connect-timeout 20 -m 60 \
      -o /dev/null -w '%{url_effective}' "$mirrored" || true)"
    [[ -z "$final" || "$final" == "$mirrored" ]] && {
      # -L follow: try once more with GET redirect probe
      final="$(curl -sI --http1.1 --connect-timeout 20 -m 60 -o /dev/null \
        -w '%{redirect_url}' "$mirrored" || true)"
    }
    [[ -z "$final" ]] && { warn "resolve failed (attempt $attempt)" >&2; sleep 5; continue; }

    host="$(python3 -c 'import sys,urllib.parse as u; print(u.urlparse(sys.argv[1]).hostname or "")' "$final" 2>/dev/null || true)"
    if [[ -n "$host" ]] && ! curl -s --http1.1 --connect-timeout 8 -m 10 \
         -o /dev/null "https://${host}/" 2>/dev/null; then
      # soft check — dig may work while HTTPS fails; still try download
      if ! dig +short +time=3 "$host" 2>/dev/null | grep -q .; then
        warn "CDN host DNS unresolved: $host — wait & re-resolve (attempt $attempt)" >&2
        sleep 8
        continue
      fi
    fi

    remote_size="$(curl -sI --http1.1 --connect-timeout 20 -m 45 "$final" \
      | tr -d '\r' | awk 'tolower($1)=="content-length:"{print $2}' | tail -1)"
    local_size="$(stat -f%z "$dest" 2>/dev/null || echo 0)"
    if [[ -n "$remote_size" && "$local_size" == "$remote_size" ]]; then
      ok "already complete: $dest ($local_size bytes)" >&2
      echo "$dest"
      return 0
    fi
    if [[ -n "$remote_size" && "$local_size" -gt 0 ]]; then
      log "resume $fname: local=$local_size / remote=$remote_size (attempt $attempt/20)" >&2
    fi

    range_code="$(curl -s --http1.1 --connect-timeout 20 -o /dev/null -w '%{http_code}' \
      -r 0-0 -m 45 "$final" || echo 000)"
    curl_rc=0
    # No long curl --retry on same URL: DNS/expiry need fresh resolve (outer loop)
    if [[ "$range_code" == "206" ]]; then
      curl -f --http1.1 --connect-timeout 30 -C - \
        --retry 1 --retry-delay 3 \
        -o "$dest" "$final" >&2 || curl_rc=$?
    else
      warn "no Range (HTTP $range_code); full re-download" >&2
      curl -f --http1.1 --connect-timeout 30 -L \
        --retry 1 --retry-delay 3 \
        -o "$dest" "$final" >&2 || curl_rc=$?
    fi
    local_size="$(stat -f%z "$dest" 2>/dev/null || echo 0)"
    if [[ "$curl_rc" -eq 0 ]]; then
      if [[ -z "$remote_size" || "$local_size" == "$remote_size" ]]; then
        echo "$dest"; return 0
      fi
      warn "curl OK but size mismatch local=$local_size remote=$remote_size — retry" >&2
    else
      # 6=DNS 18=partial 28=timeout 92=HTTP/2 — all recoverable via re-resolve+resume
      warn "interrupted (attempt $attempt, curl=$curl_rc); keeping partial $dest ($local_size bytes)" >&2
    fi
    sleep_s=15
    if [[ "$attempt" -lt 8 ]]; then
      sleep_s=$((attempt * 2))
    fi
    sleep "$sleep_s"
  done
  err "download failed: $mirrored" >&2
  return 1
}

[[ -f "$MANIFEST" ]] || { err "manifest missing: $MANIFEST"; exit 1; }
mkdir -p "$GGUF_DIR"

if [[ "$LINK_ONLY" -eq 1 ]]; then
  link_lmstudio_models "$GGUF_DIR"
  exit 0
fi

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
  link_lmstudio_models "$GGUF_DIR" || true
fi

echo
ok "In LM Studio: My Models → look under llm-gguf / ~/models/gguf"
echo "   Tip: load mmproj alongside VL GGUFs when you need vision."
