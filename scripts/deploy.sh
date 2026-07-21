#!/usr/bin/env bash
# =============================================================
# deploy.sh — 一键部署本地大模型方案
# =============================================================
# 单一数据源: config/models.manifest。升级模型只需改 manifest 再跑本脚本。
#
# 用法:
#   ./scripts/deploy.sh                # 部署 manifest 中所有 a/b/c 档
#   ./scripts/deploy.sh main           # 只部署某一档 (main|deep|fast)
#   ./scripts/deploy.sh --check        # 只体检环境+对账，不安装
#   ./scripts/deploy.sh --prune        # 部署后删除 retired 档模型（需确认）
#   ./scripts/deploy.sh main --gguf    # 强制走 GGUF 手动下载路径（跳过 ollama pull）
#
# 安装策略（每个模型）:
#   1) 首选 ollama pull <tag>       —— 原生断点续传，最省事
#   2) 失败则回退 GGUF 下载 + 导入   —— curl -C - 断点续传，域名走镜像
#
# 网络: HF_ENDPOINT 环境变量可覆盖镜像（默认 hf-mirror.com）。
#   export HF_ENDPOINT=https://huggingface.co   # 如直连可用
# =============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/config/models.manifest"
GGUF_DIR="${LLM_GGUF_DIR:-$HOME/Downloads/llm-gguf}"
HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"
IMPORT="$ROOT/scripts/import-gguf.sh"

# ---- 参数解析 ----
ONLY_TIER=""
DO_CHECK=0
DO_PRUNE=0
FORCE_GGUF=0
for arg in "$@"; do
  case "$arg" in
    main|deep|fast) ONLY_TIER="$arg" ;;
    a) ONLY_TIER="deep" ;;   # 旧档位兼容
    b) ONLY_TIER="main" ;;
    c) ONLY_TIER="fast" ;;
    --check)      DO_CHECK=1 ;;
    --prune)      DO_PRUNE=1 ;;
    --gguf)       FORCE_GGUF=1 ;;
    -h|--help)    grep -E '^#( |=)' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)            echo "未知参数: $arg (用 --help 看用法)"; exit 1 ;;
  esac
done

log()  { printf '\033[1;36m>>> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!!! %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m OK %s\033[0m\n' "$*"; }
err()  { printf '\033[1;31mERR %s\033[0m\n' "$*"; }

[[ -f "$MANIFEST" ]] || { err "找不到 manifest: $MANIFEST"; exit 1; }

# ---- 环境体检 ----
preflight() {
  log "环境体检"
  command -v ollama >/dev/null 2>&1 || { err "未安装 ollama —— 见 docs/install.md"; exit 1; }
  ok "ollama $(ollama --version 2>/dev/null | head -1)"
  if ! curl -s -m 5 -o /dev/null "http://127.0.0.1:11434/api/tags"; then
    warn "Ollama daemon 未响应，尝试启动…"
    ( ollama serve >/dev/null 2>&1 & )
    sleep 3
    curl -s -m 5 -o /dev/null "http://127.0.0.1:11434/api/tags" \
      && ok "daemon 已就绪" || { err "daemon 起不来，手动 'ollama serve' 后重试"; exit 1; }
  else
    ok "daemon 在线 (127.0.0.1:11434)"
  fi
  local free
  free="$(df -h /System/Volumes/Data 2>/dev/null | tail -1 | awk '{print $4}')"
  ok "可用磁盘: ${free:-未知}"
}

installed_tags() { ollama list 2>/dev/null | awk 'NR>1{print $1}'; }

# ---- GGUF 断点续传下载 ----
download_gguf() {
  # $1 url  -> 回显本地绝对路径
  # 坑: `curl -L -C -` 会把 Range 头发给第一跳(镜像的 302 页,不支持 Range),
  #     导致 "HTTP server doesn't seem to support byte ranges"。
  #     必须先解析出最终 CDN URL(支持 206),再对它续传;
  #     且 CDN 签名 URL 会过期,每次重试都要重新解析。
  local url="$1" mirrored fname dest final attempt
  mirrored="${url/https:\/\/huggingface.co/$HF_ENDPOINT}"
  fname="$(basename "$url")"
  dest="$GGUF_DIR/$fname"
  mkdir -p "$GGUF_DIR"
  log "下载(断点续传) $fname  <- $HF_ENDPOINT" >&2
  for attempt in 1 2 3 4 5; do
    final="$(curl -sIL -o /dev/null -w '%{url_effective}' -m 30 "$mirrored" || true)"
    [[ -z "$final" ]] && { warn "解析最终 URL 失败 (attempt $attempt)" >&2; sleep 3; continue; }
    # 已完整则直接跳过(避免 -C - 对完整文件收 416 误判失败)
    local remote_size local_size
    remote_size="$(curl -sI -m 30 "$final" | tr -d '\r' | awk 'tolower($1)=="content-length:"{print $2}' | tail -1)"
    local_size="$(stat -f%z "$dest" 2>/dev/null || echo 0)"
    if [[ -n "$remote_size" && "$local_size" == "$remote_size" ]]; then
      ok "已存在完整文件: $dest ($local_size bytes)" >&2
      echo "$dest"
      return 0
    fi
    # 探测最终 URL 是否支持 Range(大 GGUF 走 CDN 支持 206;小文件可能不支持)
    local range_code
    range_code="$(curl -s -o /dev/null -w '%{http_code}' -r 0-0 -m 30 "$final" || echo 000)"
    if [[ "$range_code" == "206" ]]; then
      # 支持断点续传
      if curl -f -C - --retry 3 --retry-delay 3 -o "$dest" "$final" >&2; then
        echo "$dest"
        return 0
      fi
      warn "下载中断 (attempt $attempt)，已保留部分文件将续传: $dest" >&2
    else
      # 不支持 Range → 整文件重下(小文件场景,代价可忽略)
      warn "服务器不支持 Range(HTTP $range_code)，整文件下载" >&2
      if curl -f -L --retry 3 --retry-delay 3 -o "$dest" "$final" >&2; then
        echo "$dest"
        return 0
      fi
      warn "下载失败 (attempt $attempt): $dest" >&2
    fi
    sleep 3
  done
  err "下载失败(5 次尝试): $mirrored" >&2
  return 1
}

# ---- 安装单个模型 ----
install_model() {
  local tier="$1" tag="$2" ctx="$3" gguf_url="$4" mmproj_url="$5"
  if installed_tags | grep -qx "$tag"; then
    ok "[$tier] 已安装: $tag"
    return 0
  fi

  # 路径 1: ollama pull（原生断点续传）
  if [[ "$FORCE_GGUF" -eq 0 ]]; then
    log "[$tier] ollama pull $tag"
    if ollama pull "$tag"; then
      ok "[$tier] pull 完成: $tag"
      return 0
    fi
    warn "[$tier] pull 失败，回退 GGUF 手动导入"
  fi

  # 路径 2: GGUF 下载 + import
  [[ -n "$gguf_url" ]] || { err "[$tier] $tag 无 GGUF 回退直链，跳过"; return 1; }
  local gguf localname
  gguf="$(download_gguf "$gguf_url")" || return 1
  [[ -n "$mmproj_url" ]] && download_gguf "$mmproj_url" >/dev/null || true
  # 用 tag 派生一个合法本地名（冒号/斜杠换连字符）
  localname="$(echo "$tag" | tr ':/' '--')"
  log "[$tier] 导入 ollama: $localname (ctx=$ctx)"
  "$IMPORT" "$localname" "$gguf" "$ctx"
  ok "[$tier] GGUF 导入完成: $localname （注意: 本地名与官方 tag 不同）"
}

# ---- 退役清理 ----
prune_retired() {
  local rows tag found=0
  rows="$(grep -E '^retired\|' "$MANIFEST" | cut -d'|' -f2)"
  [[ -z "$rows" ]] && { ok "无 retired 条目"; return 0; }
  echo; warn "以下 retired 模型将被删除:"
  while IFS= read -r tag; do
    [[ -z "$tag" ]] && continue
    if installed_tags | grep -qx "$tag"; then echo "  - $tag (已装)"; found=1; fi
  done <<< "$rows"
  [[ "$found" -eq 0 ]] && { ok "retired 模型均未安装，无需清理"; return 0; }
  read -r -p "确认删除以上模型？[y/N] " ans
  [[ "$ans" =~ ^[yY]$ ]] || { warn "已取消清理"; return 0; }
  while IFS= read -r tag; do
    [[ -z "$tag" ]] && continue
    installed_tags | grep -qx "$tag" && { ollama rm "$tag" && ok "已删 $tag"; }
  done <<< "$rows"
}

# ---- 对账报告 ----
reconcile() {
  echo; log "对账 (manifest vs 已装)"
  local tier tag rest
  while IFS='|' read -r tier tag ctx rest; do
    [[ "$tier" =~ ^#|^$ ]] && continue
    [[ "$tier" == "retired" ]] && continue
    [[ -n "$ONLY_TIER" && "$tier" != "$ONLY_TIER" ]] && continue
    if installed_tags | grep -qx "$tag"; then
      printf '  \033[1;32m✓\033[0m [%s] %s\n' "$tier" "$tag"
    else
      printf '  \033[1;31m✗\033[0m [%s] %s (缺)\n' "$tier" "$tag"
    fi
  done < "$MANIFEST"
}

# ================= 主流程 =================
preflight

if [[ "$DO_CHECK" -eq 1 ]]; then
  reconcile
  exit 0
fi

log "读取 manifest: $MANIFEST  (镜像: $HF_ENDPOINT)"
while IFS='|' read -r tier tag ctx gguf_url mmproj_url; do
  [[ "$tier" =~ ^#|^$ ]] && continue
  [[ "$tier" == "retired" ]] && continue
  [[ -n "$ONLY_TIER" && "$tier" != "$ONLY_TIER" ]] && continue
  # 去除可能的首尾空白
  tag="$(echo "$tag" | xargs)"
  install_model "$tier" "$tag" "${ctx:-32768}" "${gguf_url:-}" "${mmproj_url:-}"
done < "$MANIFEST"

[[ "$DO_PRUNE" -eq 1 ]] && prune_retired

"$ROOT/scripts/sync-registry.sh" || true
reconcile
echo
ok "部署完成。Cursor/Agent → http://127.0.0.1:11434/v1"
