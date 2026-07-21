#!/usr/bin/env bash
# Quick smoke: generate one short reply from a named model.
set -euo pipefail
MODEL="${1:-qwen3.6:35b-a3b-q4_K_M}"
PROMPT="${2:-用一句话介绍你自己}"
echo "Testing model: $MODEL"
time ollama run "$MODEL" "$PROMPT"
