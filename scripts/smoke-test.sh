#!/usr/bin/env bash
# =============================================================
# smoke-test.sh — model smoke test: LLM reply + tok/s, image-gen output
# =============================================================
# Usage:
#   lm test                    # test the main LLM tier
#   lm test fast               # tier name: main | deep | fast
#   lm test all                # test EVERYTHING: all LLM tiers + all image models
#   lm test all-llm            # all LLM tiers only
#   lm test all-image          # all image-gen models only
#   lm test qwen3.5:9b         # or any installed ollama tag (see: ollama list)
#   lm test fast "1+1=?"       # custom prompt as 2nd arg (LLM runs only)
#
# The model argument accepts:
#   all                        -> every LLM tier + every image model (both manifests)
#   all-llm | all-image        -> scope to one manifest
#   main | deep | fast         -> resolved to the tag in config/models.manifest
#   <any ollama tag>           -> used as-is
#
# Notes on 'all':
#   - LLM models run SEQUENTIALLY with keep_alive=0 so each unloads after
#     its test — two large models never coexist in RAM (48GB budget).
#   - Image models generate a small 512x512 test image into a temp dir
#     via scripts/gen-image.sh (config/image-models.manifest).
# =============================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/config/models.manifest"
IMG_MANIFEST="$ROOT/config/image-models.manifest"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  grep -E '^#( |=)' "$0" | sed 's/^# \{0,1\}//'
  echo "Available LLM tiers (config/models.manifest):"
  grep -E '^(main|deep|fast)\|' "$MANIFEST" | awk -F'|' '{printf "  %-6s -> %s\n", $1, $2}'
  echo
  echo "Image-gen models (config/image-models.manifest):"
  grep -E '^(primary|alt)\|' "$IMG_MANIFEST" | awk -F'|' '{printf "  %-8s -> %s\n", $1, $2}'
  echo
  echo "Installed ollama tags:"
  ollama list 2>/dev/null | awk 'NR>1{print "  "$1}' || echo "  (daemon not running)"
  exit 0
fi

MODEL="${1:-main}"
PROMPT="${2:-Introduce yourself in one sentence. /no_think}"

## test_one <tag> <prompt> [keep_alive] — one LLM smoke test: reply + tok/s
test_one() {
  local tag="$1" prompt="$2" keep="${3:-}"
  echo "Smoke test (LLM): $tag"
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

## test_image_one <model-id> — one image-gen smoke test: 512px, fixed seed, temp output
test_image_one() {
  local id="$1"
  local out; out="$(mktemp -d)/smoke-$id.png"
  echo "Smoke test (image): $id"
  local t0 t1
  t0=$(date +%s)
  if "$ROOT/scripts/gen-image.sh" --model "$id" --size 512x512 --seed 7 --out "$out" \
       "a small red bird on a green branch, simple background" >/dev/null 2>&1 \
     && [[ -s "$out" ]]; then
    t1=$(date +%s)
    echo "Image: $out ($(du -h "$out" | awk '{print $1}'), $((t1 - t0))s)"
    return 0
  fi
  echo "ERROR: image generation failed for $id (run manually: lm image --model $id \"test\")"
  return 1
}

run_all_llm() {
  local fail=0 tier tag _
  while IFS='|' read -r tier tag _; do
    [[ "$tier" =~ ^#|^$|^retired$ ]] && continue
    tag="$(echo "$tag" | xargs)"
    echo
    echo "===== [LLM: $tier] ====="
    test_one "$tag" "$PROMPT" 0 || fail=1
  done < "$MANIFEST"
  return "$fail"
}

run_all_image() {
  local fail=0 role id _
  while IFS='|' read -r role id _; do
    [[ "$role" =~ ^#|^$|^retired$ ]] && continue
    echo
    echo "===== [image: $role] ====="
    test_image_one "$id" || fail=1
  done < "$IMG_MANIFEST"
  return "$fail"
}

case "$MODEL" in
  all)
    FAIL=0
    run_all_llm   || FAIL=1
    run_all_image || FAIL=1
    echo
    if [[ "$FAIL" -eq 0 ]]; then echo "ALL MODELS PASSED (LLM + image)"; else echo "SOME MODELS FAILED"; exit 1; fi
    exit 0 ;;
  all-llm)
    run_all_llm && { echo; echo "ALL LLM TIERS PASSED"; } || { echo; echo "SOME LLM TIERS FAILED"; exit 1; }
    exit 0 ;;
  all-image)
    run_all_image && { echo; echo "ALL IMAGE MODELS PASSED"; } || { echo; echo "SOME IMAGE MODELS FAILED"; exit 1; }
    exit 0 ;;
esac

## Tier name -> manifest tag
if grep -qE "^$MODEL\|" "$MANIFEST" 2>/dev/null; then
  MODEL="$(grep -E "^$MODEL\|" "$MANIFEST" | head -1 | cut -d'|' -f2)"
fi
test_one "$MODEL" "$PROMPT"
