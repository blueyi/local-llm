#!/usr/bin/env bash
# Backward-compatible wrapper; implementation lives in pull-gguf.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$HOME/models/gguf}"
LLM_GGUF_DIR="$SRC" exec "$ROOT/scripts/pull-gguf.sh" --link-only
