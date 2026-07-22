#!/usr/bin/env bash
# Import a local GGUF into Ollama via Modelfile.
# Usage:
#   ./scripts/import-gguf.sh <ollama-name> <path-to.gguf> [num_ctx]
# Example:
#   ./scripts/import-gguf.sh qwen3-coder-b-q4 ~/models/gguf/Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf 32768
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${1:-}"
GGUF="${2:-}"
CTX="${3:-32768}"

if [[ -z "$NAME" || -z "$GGUF" ]]; then
  echo "Usage: $0 <ollama-name> <path-to.gguf> [num_ctx]"
  exit 1
fi
if [[ ! -f "$GGUF" ]]; then
  echo "ERROR: file not found: $GGUF"
  exit 1
fi
# Reject incomplete downloads
case "$GGUF" in
  *.aria2|*.download|*.part|*-partial) echo "ERROR: looks incomplete: $GGUF"; exit 1 ;;
esac
command -v ollama >/dev/null 2>&1 || { echo "ollama not installed"; exit 1; }

ABS="$(cd "$(dirname "$GGUF")" && pwd)/$(basename "$GGUF")"
MF="$ROOT/config/Modelfiles/${NAME}.Modelfile"
cat >"$MF" <<EOF
FROM ${ABS}
PARAMETER num_ctx ${CTX}
EOF

echo "Modelfile -> $MF"
echo "Creating ollama model: $NAME"
ollama create "$NAME" -f "$MF"
echo "OK. Try: ollama run $NAME"
"$ROOT/scripts/sync-registry.sh" || true
