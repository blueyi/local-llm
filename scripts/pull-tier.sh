#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TIER="${1:-}"
if [[ -z "$TIER" || ! "$TIER" =~ ^[abcABC]$ ]]; then
  echo "Usage: $0 <a|b|c>"
  echo "  a = highest quality (q8)"
  echo "  b = balanced (q4_K_M daily default)"
  echo "  c = max speed (8b)"
  exit 1
fi
TIER="$(echo "$TIER" | tr 'A-C' 'a-c')"
command -v ollama >/dev/null 2>&1 || { echo "ollama not installed"; exit 1; }

pull_one() {
  local name="$1"
  echo ">>> ollama pull $name"
  if ollama pull "$name"; then
    echo "OK: $name"
    return 0
  else
    echo "WARN: failed to pull $name"
    return 1
  fi
}

case "$TIER" in
  b)
    pull_one "qwen3.6:35b-a3b-q4_K_M" || true
    ;;
  a)
    pull_one "qwen3.6:27b-q8_0" || true
    ;;
  c)
    pull_one "qwen3.5:9b" || true
    ;;
esac

echo
"$ROOT/scripts/sync-registry.sh" || true
echo "Update docs/models-registry.md status + docs/changelog.md if needed."
