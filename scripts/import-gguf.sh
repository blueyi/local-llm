#!/usr/bin/env bash
# Import a local GGUF into Ollama via Modelfile.
# Usage:
#   ./scripts/import-gguf.sh <ollama-name> <path-to.gguf> [num_ctx]
# Example:
#   ./scripts/import-gguf.sh local-main ~/models/gguf/model-Q4_K_M.gguf 32768
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${1:-}"
GGUF="${2:-}"
CTX="${3:-32768}"
MMPROJ="${4:-}"

if [[ -z "$NAME" || -z "$GGUF" ]]; then
  echo "Usage: $0 <ollama-name> <path-to.gguf> [num_ctx] [mmproj.gguf]"
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
SAFE_NAME="$(printf '%s' "$NAME" | tr '/:' '__')"
MF="$ROOT/config/Modelfiles/${SAFE_NAME}.Modelfile"
{
  echo "FROM ${ABS}"
  if [[ -n "$MMPROJ" ]]; then
    [[ -f "$MMPROJ" ]] || { echo "ERROR: mmproj not found: $MMPROJ"; exit 1; }
    MMPROJ_ABS="$(cd "$(dirname "$MMPROJ")" && pwd)/$(basename "$MMPROJ")"
    echo "FROM ${MMPROJ_ABS}"
  fi
  echo "PARAMETER num_ctx ${CTX}"
} >"$MF"

echo "Modelfile -> $MF"
echo "Creating ollama model: $NAME"
ollama create "$NAME" -f "$MF"
echo "OK. Try: ollama run $NAME"
"$ROOT/scripts/sync-registry.sh" || true
