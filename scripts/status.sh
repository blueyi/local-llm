#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "=== local-llm status ==="
echo "Knowledge base: $ROOT"
echo
if command -v ollama >/dev/null 2>&1; then
  echo "Ollama: $(ollama --version 2>/dev/null || echo unknown)"
  echo "--- ollama list ---"
  ollama list 2>/dev/null || echo "(daemon not running or empty)"
  echo "--- ollama ps ---"
  ollama ps 2>/dev/null || true
else
  echo "Ollama: not installed"
fi
echo
if [ -d "$HOME/.ollama" ]; then
  echo "Ollama data: $(du -sh "$HOME/.ollama" 2>/dev/null | awk '{print $1}') ($HOME/.ollama)"
else
  echo "Ollama data: (no ~/.ollama yet)"
fi
for p in "$HOME/.lmstudio/models" "$HOME/Library/Application Support/LM Studio"; do
  if [ -e "$p" ]; then
    echo "LM Studio path exists: $p ($(du -sh "$p" 2>/dev/null | awk '{print $1}'))"
  fi
done
if [ -d "/Applications/LM Studio.app" ]; then
  echo "LM Studio.app: installed"
else
  echo "LM Studio.app: not found in /Applications"
fi
echo
echo "Free disk (Data):"
df -h /System/Volumes/Data 2>/dev/null | tail -1 || df -h / | tail -1
