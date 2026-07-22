#!/usr/bin/env bash
# status.sh — 本地模型方案总览（lm status）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODELS_ROOT="$HOME/models"

echo "=== local-llm status ==="
echo "知识库: $ROOT"
echo

echo "--- 权重统一目录 ($MODELS_ROOT) ---"
if [ -d "$MODELS_ROOT" ]; then
  du -sh "$MODELS_ROOT"/* 2>/dev/null || echo "(空)"
  # symlink 健康检查
  for link in "$HOME/.ollama/models" "$HOME/.lmstudio/models/llm-gguf"; do
    if [ -L "$link" ]; then
      tgt="$(readlink "$link")"
      if [ -e "$link" ]; then echo "link OK: $link -> $tgt"; else echo "link BROKEN: $link -> $tgt"; fi
    fi
  done
else
  echo "(不存在 — 权重目录未初始化)"
fi
echo

if command -v ollama >/dev/null 2>&1; then
  echo "Ollama: $(ollama --version 2>/dev/null || echo unknown)"
  echo "--- ollama list ---"
  ollama list 2>/dev/null || echo "(daemon 未运行或为空)"
  echo "--- ollama ps (当前加载) ---"
  ollama ps 2>/dev/null || true
else
  echo "Ollama: 未安装"
fi
echo

echo "--- 文生图 (mflux) ---"
if command -v mflux-generate-flux2 >/dev/null 2>&1; then
  echo "mflux: 已安装 ($(command -v mflux-generate-flux2))"
else
  echo "mflux: 未安装 (uv tool install mflux)"
fi
if [ -f "$ROOT/config/image-models.manifest" ]; then
  grep -E '^(primary|alt)\|' "$ROOT/config/image-models.manifest" | while IFS='|' read -r role id repo _; do
    d="$MODELS_ROOT/image-gen/$(basename "$repo")"
    if [ -d "$d" ]; then echo "  ✓ [$role] $id ($(du -sh "$d" 2>/dev/null | awk '{print $1}'))"; else echo "  ✗ [$role] $id (缺权重: lm pull-image $repo)"; fi
  done
fi
echo

echo "--- 磁盘 (Data) ---"
df -h /System/Volumes/Data 2>/dev/null | tail -1 || df -h / | tail -1
