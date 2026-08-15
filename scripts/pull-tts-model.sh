#!/usr/bin/env bash
# Backward-compatible wrapper; implementation lives in pull-hf-model.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec "$ROOT/scripts/pull-hf-model.sh" --kind tts "$@"
