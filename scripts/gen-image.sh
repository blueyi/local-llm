#!/usr/bin/env bash
# =============================================================
# gen-image.sh — 本地文生图 / 图生图统一包装（读 image-models.manifest）
# =============================================================
# 用法:
#   ./scripts/gen-image.sh "a cute orange kitten"                    # primary 模型出图
#   ./scripts/gen-image.sh --model z-image-turbo "portrait photo"    # 指定模型
#   ./scripts/gen-image.sh --edit in.png "make the sky sunset" out.png  # 改图(仅支持 EDIT_CLI 的模型)
#   ./scripts/gen-image.sh --size 1024x576 --steps 6 --seed 42 "..." # 精细控制
#
# 选项:
#   --model <id>     模型短名 (见 config/image-models.manifest, 默认 primary)
#   --size  WxH      分辨率 (默认 768x768, 用 16 的倍数)
#   --steps N        采样步数 (默认取 manifest)
#   --seed  N        随机种子 (默认随机)
#   --out   PATH     输出文件 (默认 ~/Pictures/gen/<timestamp>.png)
#   --edit  IN.png   图生图模式: 以 IN.png 为底图按 prompt 修改
# =============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/config/image-models.manifest"
WEIGHTS_ROOT="${IMAGE_MODELS_DIR:-$HOME/models/image-gen}"

MODEL_ID="" SIZE="768x768" STEPS="" SEED="" OUT="" EDIT_IN="" PROMPT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL_ID="$2"; shift 2 ;;
    --size)  SIZE="$2"; shift 2 ;;
    --steps) STEPS="$2"; shift 2 ;;
    --seed)  SEED="$2"; shift 2 ;;
    --out)   OUT="$2"; shift 2 ;;
    --edit)  EDIT_IN="$2"; shift 2 ;;
    -h|--help) grep -E '^#( |=)' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) if [[ -z "$PROMPT" ]]; then PROMPT="$1"; else OUT="${OUT:-$1}"; fi; shift ;;
  esac
done
[[ -n "$PROMPT" ]] || { echo "ERROR: 缺 prompt (用 --help 看用法)"; exit 1; }

# ---- 从 manifest 解析模型行 ----
pick_row() {
  # 无 --model → primary 行；有 → 按 MODEL_ID 匹配
  if [[ -z "$MODEL_ID" ]]; then
    grep -E '^primary\|' "$MANIFEST" | head -1
  else
    grep -E "^(primary|alt)\|$MODEL_ID\|" "$MANIFEST" | head -1
  fi
}
ROW="$(pick_row)"
[[ -n "$ROW" ]] || { echo "ERROR: manifest 中找不到模型 '$MODEL_ID'"; grep -E '^(primary|alt)\|' "$MANIFEST" | cut -d'|' -f1,2; exit 1; }
IFS='|' read -r ROLE ID HF_REPO GEN_CLI EDIT_CLI BASE_ARG DEF_STEPS <<< "$ROW"

MODEL_DIR="$WEIGHTS_ROOT/$(basename "$HF_REPO")"
[[ -d "$MODEL_DIR" ]] || { echo "ERROR: 权重缺失 $MODEL_DIR — 先跑: lm pull-image $HF_REPO"; exit 1; }

STEPS="${STEPS:-$DEF_STEPS}"
WIDTH="${SIZE%x*}"; HEIGHT="${SIZE#*x}"
if [[ -z "$OUT" ]]; then
  mkdir -p "$HOME/Pictures/gen"
  OUT="$HOME/Pictures/gen/$(date +%Y%m%d-%H%M%S)-$ID.png"
fi

CMD=()
if [[ -n "$EDIT_IN" ]]; then
  [[ -n "$EDIT_CLI" ]] || { echo "ERROR: 模型 $ID 不支持改图（EDIT_CLI 为空，用 flux2-klein-4b）"; exit 1; }
  [[ -f "$EDIT_IN" ]] || { echo "ERROR: 底图不存在: $EDIT_IN"; exit 1; }
  CMD=("$EDIT_CLI" --model "$MODEL_DIR" --image-path "$EDIT_IN")
else
  CMD=("$GEN_CLI" --model "$MODEL_DIR")
fi
[[ -n "$BASE_ARG" ]] && CMD+=(--base-model "$BASE_ARG")
CMD+=(--prompt "$PROMPT" --width "$WIDTH" --height "$HEIGHT" --steps "$STEPS" --output "$OUT")
[[ -n "$SEED" ]] && CMD+=(--seed "$SEED")

command -v "${CMD[0]}" >/dev/null 2>&1 || { echo "ERROR: 未安装 mflux — uv tool install mflux"; exit 1; }
echo ">>> [$ID] ${WIDTH}x${HEIGHT} steps=$STEPS ${EDIT_IN:+edit=$EDIT_IN }-> $OUT"
"${CMD[@]}"
echo "DONE: $OUT"
