#!/usr/bin/env bash
# Shared Hugging Face mirror listing and resumable file download helpers.

# Callers must source common.sh first and define HF_MIRROR (or rely on the
# default below). Functions intentionally write progress to stderr so callers
# can safely capture returned paths.
HF_MIRROR="${HF_MIRROR:-https://hf-mirror.com}"

hf_list_files() {
  local repo="$1" skip_samples="${2:-0}"
  curl -fsSL -m 30 "$HF_MIRROR/api/models/$repo" |
    SKIP_SAMPLES="$skip_samples" python3 -c '
import json, os, sys
skip_samples = os.environ.get("SKIP_SAMPLES") == "1"
for item in (json.load(sys.stdin).get("siblings") or []):
    name = item.get("rfilename", "")
    if not name or name.startswith(".") or (skip_samples and name.startswith("samples/")):
        continue
    print(name)
'
}

hf_download_file() {
  local repo="$1" file="$2" dest_root="$3"
  local mirrored final remote_size local_size range_code curl_rc
  local dest="$dest_root/$file"
  mirrored="$HF_MIRROR/$repo/resolve/main/$file"
  mkdir -p "$(dirname "$dest")"
  log "Downloading $file <- $HF_MIRROR" >&2

  for attempt in 1 2 3 4 5; do
    final="$(curl -fsSIL -o /dev/null -w '%{url_effective}' -m 30 "$mirrored" || true)"
    [[ -n "$final" ]] || { warn "resolve failed (attempt $attempt/5): $file" >&2; sleep 2; continue; }
    remote_size="$(curl -fsSI -m 30 "$final" | tr -d '\r' | awk 'tolower($1)=="content-length:" {print $2}' | tail -1 || true)"
    local_size="$(stat -f%z "$dest" 2>/dev/null || echo 0)"
    if [[ -n "$remote_size" && "$local_size" == "$remote_size" ]]; then
      ok "already complete: $dest ($local_size bytes)" >&2
      return 0
    fi
    range_code="$(curl -sS -o /dev/null -w '%{http_code}' -r 0-0 -m 30 "$final" || echo 000)"
    curl_rc=0
    if [[ "$range_code" == "206" ]]; then
      curl -fS --http1.1 -C - --retry 2 --retry-delay 2 -o "$dest" "$final" >&2 || curl_rc=$?
    else
      warn "server does not support Range (HTTP $range_code); downloading whole file" >&2
      curl -fS --http1.1 -L --retry 2 --retry-delay 2 -o "$dest" "$final" >&2 || curl_rc=$?
    fi
    local_size="$(stat -f%z "$dest" 2>/dev/null || echo 0)"
    if [[ "$curl_rc" -eq 0 && ( -z "$remote_size" || "$local_size" == "$remote_size" ) ]]; then
      ok "downloaded: $dest" >&2
      return 0
    fi
    warn "download incomplete (attempt $attempt/5, curl=$curl_rc, bytes=$local_size)" >&2
    sleep "$((attempt * 2))"
  done
  err "download failed after 5 attempts: $mirrored"
  return 1
}

hf_download_repo() {
  local repo="$1" dest_root="$2" skip_samples="${3:-0}"
  local dest="$dest_root/$(basename "$repo")" file files
  mkdir -p "$dest"
  files="$(hf_list_files "$repo" "$skip_samples")" || {
    err "could not list files for HF repo: $repo"
    return 1
  }
  [[ -n "$files" ]] || {
    err "HF repo has no downloadable files: $repo"
    return 1
  }
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    hf_download_file "$repo" "$file" "$dest"
  done <<< "$files"
  du -sh "$dest" >&2 || true
  printf '%s\n' "$dest"
}
