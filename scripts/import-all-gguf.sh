#!/usr/bin/env bash
# Import active manifest GGUF files found in ~/models/gguf (or $1).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/common.sh"
MANIFEST="$ROOT/config/models.manifest"
DIR="${1:-$HOME/models/gguf}"
IMPORT="$ROOT/scripts/import-gguf.sh"
[[ -d "$DIR" ]] || { err "directory not found: $DIR"; exit 1; }
count=0
while IFS='|' read -r tier tag ctx url _mmproj; do
  [[ "$tier" =~ ^#|^$|retired$ ]] && continue
  file="$(basename "${url:-}")"
  [[ -n "$file" ]] || { warn "[$tier] $tag has no GGUF URL; skip"; continue; }
  found="$(find "$DIR" -maxdepth 1 -type f -name "$file" ! -name '*.aria2' ! -name '*.download' ! -name '*.part' -print -quit 2>/dev/null || true)"
  if [[ -n "$found" ]]; then
    log "[$tier] importing $found as $tag"
    "$IMPORT" "$tag" "$found" "${ctx:-32768}"
    count=$((count + 1))
  else
    warn "[$tier] missing $file in $DIR (run lm pull-gguf $tier)"
  fi
done < "$MANIFEST"
ok "Imported $count manifest GGUF model(s)"
ollama list || true
