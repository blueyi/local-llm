#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REG="$ROOT/docs/models-registry.md"
if ! command -v ollama >/dev/null 2>&1; then
  echo "ollama not installed; skip"
  exit 0
fi
TMP="$(mktemp)"
{
  echo '```'
  ollama list 2>/dev/null || echo "(empty or daemon down)"
  echo '```'
} >"$TMP"
if grep -q 'BEGIN OLLAMA LIST' "$REG"; then
  awk -v f="$TMP" '
    /BEGIN OLLAMA LIST/ { print; system("cat " f); skip=1; next }
    /END OLLAMA LIST/ { skip=0; print; next }
    !skip { print }
  ' "$REG" >"$REG.tmp" && mv "$REG.tmp" "$REG"
  echo "Updated Ollama list section in docs/models-registry.md"
else
  echo "Markers not found in models-registry.md"
  cat "$TMP"
fi
rm -f "$TMP"
