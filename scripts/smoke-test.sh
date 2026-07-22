#!/usr/bin/env bash
# smoke-test.sh — 单模型冒烟：一句回复 + tok/s（lm test [tier|tag] [prompt]）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODEL="${1:-main}"
PROMPT="${2:-用一句话介绍你自己 /no_think}"

# 档位名 → manifest tag
if grep -qE "^$MODEL\|" "$ROOT/config/models.manifest" 2>/dev/null; then
  MODEL="$(grep -E "^$MODEL\|" "$ROOT/config/models.manifest" | head -1 | cut -d'|' -f2)"
fi

echo "冒烟: $MODEL"
BODY="$(SM_MODEL="$MODEL" SM_PROMPT="$PROMPT" python3 -c 'import json,os;print(json.dumps({"model":os.environ["SM_MODEL"],"prompt":os.environ["SM_PROMPT"],"stream":False}))')"
curl -s http://127.0.0.1:11434/api/generate -d "$BODY" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if "error" in d:
    print("ERROR:", d["error"]); sys.exit(1)
tps = d["eval_count"] / (d["eval_duration"] / 1e9)
load = d.get("load_duration", 0) / 1e9
ec = d["eval_count"]
print("回复:", d["response"].strip()[:120])
print(f"速度: {tps:.1f} tok/s  (加载 {load:.1f}s, 生成 {ec} tok)")
'
