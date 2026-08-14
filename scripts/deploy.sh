#!/usr/bin/env bash
# =============================================================
# deploy.sh — one-command deployment of the local LLM stack
# =============================================================
# Single source of truth: config/models.manifest.
# Upgrading a model = edit the manifest, then re-run this script.
#
# Usage:
#   ./scripts/deploy.sh                # deploy every tier in the manifest
#   ./scripts/deploy.sh main           # deploy a single tier (main|deep|fast|embed|chat)
#   ./scripts/deploy.sh --check        # health check + reconciliation only, no install
#   ./scripts/deploy.sh --prune        # deploy, then delete retired models (asks for confirmation)
#   ./scripts/deploy.sh --force        # re-pull even if already installed
#   ./scripts/deploy.sh main --gguf    # force the manual GGUF download path (skip ollama pull)
#
# Install strategy (per model):
#   1) Prefer `ollama pull <tag>`     — native resumable download, simplest
#   2) On failure, fall back to GGUF download + import — curl -C - resume, mirrored domain
#   Without --force: skip tags already present in `ollama list`
#
# Network: the HF_ENDPOINT env var overrides the mirror (default hf-mirror.com).
#   export HF_ENDPOINT=https://huggingface.co   # if direct access works
# =============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/config/models.manifest"
GGUF_DIR="${LLM_GGUF_DIR:-$HOME/models/gguf}"
HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"
IMPORT="$ROOT/scripts/import-gguf.sh"

# ---- Argument parsing ----
ONLY_TIER=""
DO_CHECK=0
DO_PRUNE=0
FORCE_PULL=0
FORCE_GGUF=0
for arg in "$@"; do
  case "$arg" in
    main|deep|fast|embed|chat|reason|rerank) ONLY_TIER="$arg" ;;
    a) ONLY_TIER="deep" ;;   # legacy tier-letter compatibility
    b) ONLY_TIER="main" ;;
    c) ONLY_TIER="fast" ;;
    --check)      DO_CHECK=1 ;;
    --prune)      DO_PRUNE=1 ;;
    --force)      FORCE_PULL=1 ;;
    --gguf)       FORCE_GGUF=1 ;;
    -h|--help)    grep -E '^#( |=)' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)            echo "Unknown argument: $arg (see --help)"; exit 1 ;;
  esac
done

log()  { printf '\033[1;36m>>> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!!! %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m OK %s\033[0m\n' "$*"; }
err()  { printf '\033[1;31mERR %s\033[0m\n' "$*"; }

[[ -f "$MANIFEST" ]] || { err "manifest not found: $MANIFEST"; exit 1; }

# ---- Environment health check ----
preflight() {
  log "Environment health check"
  command -v ollama >/dev/null 2>&1 || { err "ollama not installed — see docs/install.md"; exit 1; }
  ok "ollama $(ollama --version 2>/dev/null | head -1)"
  if ! curl -s -m 5 -o /dev/null "http://127.0.0.1:11434/api/tags"; then
    warn "Ollama daemon not responding, trying to start it..."
    ( ollama serve >/dev/null 2>&1 & )
    sleep 3
    curl -s -m 5 -o /dev/null "http://127.0.0.1:11434/api/tags" \
      && ok "daemon ready" || { err "daemon won't start; run 'ollama serve' manually and retry"; exit 1; }
  else
    ok "daemon online (127.0.0.1:11434)"
  fi
  local free
  free="$(df -h /System/Volumes/Data 2>/dev/null | tail -1 | awk '{print $4}')"
  ok "free disk: ${free:-unknown}"
}

installed_tags() { ollama list 2>/dev/null | awk 'NR>1{print $1}'; }

# ---- Resumable GGUF download ----
download_gguf() {
  # $1 url  -> echoes the local absolute path
  # Pitfall: `curl -L -C -` sends the Range header to the first hop (the
  #     mirror's 302 page, which doesn't support Range), producing
  #     "HTTP server doesn't seem to support byte ranges".
  #     We must resolve the final CDN URL first (supports 206), then resume
  #     against it; CDN signed URLs expire, so re-resolve on every retry.
  local url="$1" mirrored fname dest final attempt
  mirrored="${url/https:\/\/huggingface.co/$HF_ENDPOINT}"
  fname="$(basename "$url")"
  dest="$GGUF_DIR/$fname"
  mkdir -p "$GGUF_DIR"
  log "Downloading (resumable) $fname  <- $HF_ENDPOINT" >&2
  for attempt in 1 2 3 4 5; do
    final="$(curl -sIL -o /dev/null -w '%{url_effective}' -m 30 "$mirrored" || true)"
    [[ -z "$final" ]] && { warn "failed to resolve final URL (attempt $attempt)" >&2; sleep 3; continue; }
    # Skip if already complete (a `-C -` on a complete file returns 416 and looks like a failure)
    local remote_size local_size
    remote_size="$(curl -sI -m 30 "$final" | tr -d '\r' | awk 'tolower($1)=="content-length:"{print $2}' | tail -1)"
    local_size="$(stat -f%z "$dest" 2>/dev/null || echo 0)"
    if [[ -n "$remote_size" && "$local_size" == "$remote_size" ]]; then
      ok "complete file already present: $dest ($local_size bytes)" >&2
      echo "$dest"
      return 0
    fi
    # Probe whether the final URL supports Range (big GGUFs on the CDN return 206;
    # small files may not support it)
    local range_code
    range_code="$(curl -s -o /dev/null -w '%{http_code}' -r 0-0 -m 30 "$final" || echo 000)"
    if [[ "$range_code" == "206" ]]; then
      # Resumable
      if curl -f -C - --retry 3 --retry-delay 3 -o "$dest" "$final" >&2; then
        echo "$dest"
        return 0
      fi
      warn "download interrupted (attempt $attempt); partial file kept for resume: $dest" >&2
    else
      # No Range support -> full re-download (small-file case, negligible cost)
      warn "server does not support Range (HTTP $range_code); downloading whole file" >&2
      if curl -f -L --retry 3 --retry-delay 3 -o "$dest" "$final" >&2; then
        echo "$dest"
        return 0
      fi
      warn "download failed (attempt $attempt): $dest" >&2
    fi
    sleep 3
  done
  err "download failed (5 attempts): $mirrored" >&2
  return 1
}

# ---- Install a single model ----
install_model() {
  local tier="$1" tag="$2" ctx="$3" gguf_url="$4" mmproj_url="$5"
  if [[ "$FORCE_PULL" -eq 0 ]] && installed_tags | grep -qx "$tag"; then
    ok "[$tier] already installed: $tag"
    return 0
  fi
  if [[ "$FORCE_PULL" -eq 1 ]] && installed_tags | grep -qx "$tag"; then
    warn "[$tier] --force: re-pulling $tag"
  fi

  # Path 1: ollama pull (native resumable download)
  if [[ "$FORCE_GGUF" -eq 0 ]]; then
    log "[$tier] ollama pull $tag"
    if ollama pull "$tag"; then
      ok "[$tier] pull complete: $tag"
      return 0
    fi
    warn "[$tier] pull failed, falling back to manual GGUF import"
  fi

  # Path 2: GGUF download + import
  [[ -n "$gguf_url" ]] || { err "[$tier] $tag has no GGUF fallback URL, skipping"; return 1; }
  local gguf localname
  gguf="$(download_gguf "$gguf_url")" || return 1
  [[ -n "$mmproj_url" ]] && download_gguf "$mmproj_url" >/dev/null || true
  # Derive ollama model name: keep official tag (colons OK) so lm run matches
  localname="$tag"
  log "[$tier] importing into ollama: $localname (ctx=$ctx)"
  "$IMPORT" "$localname" "$gguf" "$ctx"
  ok "[$tier] GGUF import complete: $localname"
}

# ---- Retired model cleanup ----
prune_retired() {
  local rows tag found=0
  rows="$(grep -E '^retired\|' "$MANIFEST" | cut -d'|' -f2)"
  [[ -z "$rows" ]] && { ok "no retired entries"; return 0; }
  echo; warn "The following retired models will be deleted:"
  while IFS= read -r tag; do
    [[ -z "$tag" ]] && continue
    if installed_tags | grep -qx "$tag"; then echo "  - $tag (installed)"; found=1; fi
  done <<< "$rows"
  [[ "$found" -eq 0 ]] && { ok "no retired models installed, nothing to clean"; return 0; }
  read -r -p "Confirm deletion of the models above? [y/N] " ans
  [[ "$ans" =~ ^[yY]$ ]] || { warn "cleanup cancelled"; return 0; }
  while IFS= read -r tag; do
    [[ -z "$tag" ]] && continue
    installed_tags | grep -qx "$tag" && { ollama rm "$tag" && ok "removed $tag"; }
  done <<< "$rows"
}

# ---- Reconciliation report ----
reconcile() {
  echo; log "Reconciliation (manifest vs installed)"
  local tier tag rest
  while IFS='|' read -r tier tag ctx rest; do
    [[ "$tier" =~ ^#|^$ ]] && continue
    [[ "$tier" == "retired" ]] && continue
    [[ -n "$ONLY_TIER" && "$tier" != "$ONLY_TIER" ]] && continue
    if installed_tags | grep -qx "$tag"; then
      printf '  \033[1;32m✓\033[0m [%s] %s\n' "$tier" "$tag"
    else
      printf '  \033[1;31m✗\033[0m [%s] %s (missing)\n' "$tier" "$tag"
    fi
  done < "$MANIFEST"
}

# ================= Main =================
preflight

if [[ "$DO_CHECK" -eq 1 ]]; then
  reconcile
  exit 0
fi

log "Reading manifest: $MANIFEST  (mirror: $HF_ENDPOINT)"
while IFS='|' read -r tier tag ctx gguf_url mmproj_url; do
  [[ "$tier" =~ ^#|^$ ]] && continue
  [[ "$tier" == "retired" ]] && continue
  [[ -n "$ONLY_TIER" && "$tier" != "$ONLY_TIER" ]] && continue
  # Trim possible surrounding whitespace
  tag="$(echo "$tag" | xargs)"
  install_model "$tier" "$tag" "${ctx:-32768}" "${gguf_url:-}" "${mmproj_url:-}"
done < "$MANIFEST"

[[ "$DO_PRUNE" -eq 1 ]] && prune_retired

"$ROOT/scripts/sync-registry.sh" || true
reconcile
echo
ok "Deployment complete. Cursor/Agent -> http://127.0.0.1:11434/v1"
