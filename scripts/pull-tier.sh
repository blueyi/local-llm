#!/usr/bin/env bash
# [兼容 wrapper] pull-tier.sh 已由 deploy.sh 取代。
# 模型清单唯一来源: config/models.manifest（不要在本文件硬编码模型名）。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TIER="${1:-}"
if [[ -z "$TIER" || ! "$TIER" =~ ^[abcABC]$ ]]; then
  echo "Usage: $0 <a|b|c>   (a=质量 b=平衡 c=速度)"
  echo "推荐直接用: $ROOT/scripts/deploy.sh [a|b|c]"
  exit 1
fi
exec "$ROOT/scripts/deploy.sh" "$(echo "$TIER" | tr 'A-C' 'a-c')"
