#!/usr/bin/env bash
# Import all known-named GGUFs from ~/Downloads/llm-gguf (or $1) into Ollama.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="${1:-$HOME/Downloads/llm-gguf}"
IMPORT="$ROOT/scripts/import-gguf.sh"

if [[ ! -d "$DIR" ]]; then
  echo "Directory not found: $DIR"
  echo "Create it and place GGUF files there (see docs/manual-download.md)."
  exit 1
fi

import_if() {
  local name="$1" pattern="$2" ctx="${3:-32768}"
  local f
  f="$(find "$DIR" -maxdepth 1 -type f -iname "$pattern" ! -name '*.aria2' ! -name '*.download' ! -name '*.part' 2>/dev/null | head -1 || true)"
  if [[ -n "$f" ]]; then
    echo ">>> Found $f -> $name"
    "$IMPORT" "$name" "$f" "$ctx"
  else
    echo "--- skip $name (no match for $pattern in $DIR)"
  fi
}

# B balance
import_if "qwen3-coder-b-q4" "*Coder*30B*Q4_K_M*.gguf" 32768
import_if "qwen3.6-chat-b-q4" "*Qwen3.6*35B*Q4_K_M*.gguf" 65536
# C speed
import_if "qwen3-8b-c" "*Qwen3-8B*Q4_K_M*.gguf" 16384
# A quality
import_if "qwen3-coder-a-q8" "*Coder*30B*Q8_0*.gguf" 32768
import_if "qwen3.6-chat-a-q8" "*Qwen3.6*35B*Q8_0*.gguf" 32768

echo
echo "VL models: prefer LM Studio (main GGUF + mmproj). See docs/manual-download.md"
echo "Done. ollama list:"
ollama list || true
