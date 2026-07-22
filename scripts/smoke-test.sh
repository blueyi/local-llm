#!/usr/bin/env bash
# =============================================================
# smoke-test.sh — model smoke test: one reply + tok/s
# =============================================================
# Usage:
#   lm test                    # test the main tier
#   lm test fast               # tier name: main | deep | fast
#   lm test all                # test ALL manifest tiers sequentially (main, deep, fast)
#   lm test qwen3.5:9b         # or any installed ollama tag (see: ollama list)
#   lm test fast "1+1=?"       # custom prompt as 2nd arg (also works with 'all')
#
# The model argument accepts:
#   all                        -> every tier in config/models.manifest, one by one
#   main | deep | fast         -> resolved to the tag in config/models.manifest
#   <any ollama tag>           -> used as-is
#
# Note on 'all': models are tested SEQUENTIALLY and each one is unloaded
# after its run (keep_alive=0) — two large models never coexist in RAM.
# =============================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/config/models.manifest"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  grep -E '^#( |=)' "$0" | sed 's/^# \{0,1\}//'
  echo "Available tiers (config/models.manifest):"
  grep -E '^(main|deep|fast)\|' "$MANIFEST" | awk -F'|' '{printf "  %-6s -> %s\n", $1, $2}'
  echo
  echo "Installed ollama tags:"
  ollama list 2>/dev/null | awk 'NR>1{print "  "$1}' || echo "  (daemon not running)"
  exit 0
fi

MODEL="${1:-main}"
PROMPT="${2:-Introduce yourself in one sentence. /no_think}"

## test_one <tag> <prompt> [keep_alive] — run one smoke test, print reply + tok/s
test_one() {
  local tag="$1" prompt="$2" keep="${3:-}"
  echo "Smoke test: $tag"
  local body
  body="$(SM_MODEL="$tag" SM_PROMPT="$prompt" SM_KEEP="$keep" python3 -c '
import json, os
req = {"model": os.environ["SM_MODEL"], "prompt": os.environ["SM_PROMPT"], "stream": False}
if os.environ.get("SM_KEEP") != "":
    req["keep_alive"] = int(os.environ["SM_KEEP"])
print(json.dumps(req))')"
  curl -s http://127.0.0.1:11434/api/generate -d "$body" | python3 -c '
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
}

if [[ "$MODEL" == "all" ]]; then
  ## Sequential run over every tier; keep_alive=0 unloads each model right
  ## after its test so large models never coexist (48GB budget).
  FAIL=0
  while IFS='|' read -r tier tag _; do
    [[ "$tier" =~ ^#|^$|^retired$ ]] && continue
    tag="$(echo "$tag" | xargs)"
    echo
    echo "===== [$tier] ====="
    test_one "$tag" "$PROMPT" 0 || FAIL=1
  done < "$MANIFEST"
  echo
  if [[ "$FAIL" -eq 0 ]]; then echo "ALL TIERS PASSED"; else echo "SOME TIERS FAILED"; exit 1; fi
  exit 0
fi

## Tier name -> manifest tag
if grep -qE "^$MODEL\|" "$MANIFEST" 2>/dev/null; then
  MODEL="$(grep -E "^$MODEL\|" "$MANIFEST" | head -1 | cut -d'|' -f2)"
fi
test_one "$MODEL" "$PROMPT"
