#!/usr/bin/env bash
# =============================================================
# smoke-test.sh — single-model smoke test: one reply + tok/s
# =============================================================
# Usage:
#   lm test                    # test the main tier
#   lm test fast               # tier name: main | deep | fast
#   lm test qwen3.5:9b         # or any installed ollama tag (see: ollama list)
#   lm test fast "1+1=?"       # custom prompt as 2nd arg
#
# The model argument accepts:
#   main | deep | fast         -> resolved to the tag in config/models.manifest
#   <any ollama tag>           -> used as-is
# =============================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  grep -E '^#( |=)' "$0" | sed 's/^# \{0,1\}//'
  echo "Available tiers (config/models.manifest):"
  grep -E '^(main|deep|fast)\|' "$ROOT/config/models.manifest" | awk -F'|' '{printf "  %-6s -> %s\n", $1, $2}'
  echo
  echo "Installed ollama tags:"
  ollama list 2>/dev/null | awk 'NR>1{print "  "$1}' || echo "  (daemon not running)"
  exit 0
fi

MODEL="${1:-main}"
PROMPT="${2:-Introduce yourself in one sentence. /no_think}"

## Tier name -> manifest tag (body comment, excluded from --help output)
if grep -qE "^$MODEL\|" "$ROOT/config/models.manifest" 2>/dev/null; then
  MODEL="$(grep -E "^$MODEL\|" "$ROOT/config/models.manifest" | head -1 | cut -d'|' -f2)"
fi

echo "Smoke test: $MODEL"
BODY="$(SM_MODEL="$MODEL" SM_PROMPT="$PROMPT" python3 -c 'import json,os;print(json.dumps({"model":os.environ["SM_MODEL"],"prompt":os.environ["SM_PROMPT"],"stream":False}))')"
curl -s http://127.0.0.1:11434/api/generate -d "$BODY" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if "error" in d:
    print("ERROR:", d["error"]); sys.exit(1)
tps = d["eval_count"] / (d["eval_duration"] / 1e9)
load = d.get("load_duration", 0) / 1e9
ec = d["eval_count"]
print("Reply:", d["response"].strip()[:120])
print(f"Speed: {tps:.1f} tok/s  (load {load:.1f}s, generated {ec} tok)")
'
