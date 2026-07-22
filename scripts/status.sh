#!/usr/bin/env bash
# status.sh — local model stack overview (lm status)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODELS_ROOT="$HOME/models"

echo "=== local-llm status ==="
echo "Knowledge base: $ROOT"
echo

echo "--- Unified weights root ($MODELS_ROOT) ---"
if [ -d "$MODELS_ROOT" ]; then
  du -sh "$MODELS_ROOT"/* 2>/dev/null || echo "(empty)"
  # Symlink health check
  for link in "$HOME/.ollama/models" "$HOME/.lmstudio/models/llm-gguf"; do
    if [ -L "$link" ]; then
      tgt="$(readlink "$link")"
      if [ -e "$link" ]; then echo "link OK: $link -> $tgt"; else echo "link BROKEN: $link -> $tgt"; fi
    fi
  done
else
  echo "(missing — weights root not initialized)"
fi
echo

if command -v ollama >/dev/null 2>&1; then
  echo "Ollama: $(ollama --version 2>/dev/null || echo unknown)"
  echo "--- ollama list ---"
  ollama list 2>/dev/null || echo "(daemon not running or empty)"
  echo "--- ollama ps (currently loaded) ---"
  ollama ps 2>/dev/null || true
else
  echo "Ollama: not installed"
fi
echo

echo "--- Image generation (mflux) ---"
if command -v mflux-generate-flux2 >/dev/null 2>&1; then
  echo "mflux: installed ($(command -v mflux-generate-flux2))"
else
  echo "mflux: not installed (uv tool install mflux)"
fi
if [ -f "$ROOT/config/image-models.manifest" ]; then
  grep -E '^(primary|alt)\|' "$ROOT/config/image-models.manifest" | while IFS='|' read -r role id repo _; do
    d="$MODELS_ROOT/image-gen/$(basename "$repo")"
    if [ -d "$d" ]; then echo "  ✓ [$role] $id ($(du -sh "$d" 2>/dev/null | awk '{print $1}'))"; else echo "  ✗ [$role] $id (weights missing: lm pull-image $repo)"; fi
  done
fi
echo

echo "--- Disk (Data volume) ---"
df -h /System/Volumes/Data 2>/dev/null | tail -1 || df -h / | tail -1
