#!/usr/bin/env bash
# [兼容 wrapper] pull-tier.sh 已由 deploy.sh 取代。
# 模型清单唯一来源: config/models.manifest（不要在本文件硬编码模型名）。
# 档位: main=日常主力 deep=深度质量 fast=极限速度 (旧 a/b/c 自动映射)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TIER="${1:-}"
if [[ -z "$TIER" ]]; then
  echo "Usage: $0 <main|deep|fast>  (旧 a=deep b=main c=fast 仍兼容)"
  echo "推荐直接用: $ROOT/scripts/deploy.sh [main|deep|fast]"
  exit 1
fi
exec "$ROOT/scripts/deploy.sh" "$(echo "$TIER" | tr 'A-Z' 'a-z')"
