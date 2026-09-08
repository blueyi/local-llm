# 安装与手动下载（可复现）

标准路径三步装完；网络不好时走「手动 GGUF」回退（本文后半）。

## 标准路径

```bash
# 1. 引擎（qwen3.8 需要 Ollama ≥0.32.12；brew 若仍 0.32.11 见 docs/environment.md）
brew install ollama && brew services start ollama
ollama --version   # 确认 ≥0.32.12
uv tool install mflux                # 文生图（可选）

# 2. 统一入口上 PATH（一次性）
# PATH via my-utils (config/resetrc.bash prepends ~/workspace/local-llm/bin)
# Without my-utils: ln -sfn ~/workspace/local-llm/bin/lm ~/.local/bin/lm

# 3. 按本机硬件初始化清单，再部署
lm init --dry-run    # 看精确表命中（如 m5-max-48）或 fallback 方案
lm init --deploy      # 写清单 + lm deploy；并按 lineup pull 图/ASR/TTS
# 只要写清单、稍后手动拉权重：lm init && lm deploy
# 48GB 示例（与 full-48 清单一致；其他机型以 lm init 写入的 manifest 为准）：
# lm pull-image Runpod/FLUX.2-klein-4B-mflux-4bit
# lm pull-image filipstrand/Z-Image-Turbo-mflux-4bit

# 4. 验证
lm check && lm test fast && lm image "hello world test"
```

LM Studio（可选 GUI）：https://lmstudio.ai 下载，引擎选 **MLX**；`~/.lmstudio/models/llm-gguf` 已 symlink 到 `~/models/gguf/`。

安装后回写：`lm sync`（registry）+ `docs/changelog.md` 记一笔；版本变化改 `docs/environment.md`。

---

## 手动 GGUF 回退（`ollama pull` 不通时）

> 国内直连 `huggingface.co` 常不通 → 域名替换为 **`hf-mirror.com`**。`lm deploy` 失败时自动走此路径；下面是全手动流程。

**存放目录：`~/models/gguf/`**（勿放进本仓库 git）

### 直链清单（manifest 同源，2026-08 方案 v2.9）

| 档位 | 主模型直链 | 视觉 mmproj |
|------|-----------|-------------|
| main | https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/main/Qwen3.8-27B-Q4_K_M.gguf | 同仓库 mmproj-F16.gguf |
| deep | https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/main/Qwen3.8-27B-Q8_0.gguf | 同仓库 mmproj-F16.gguf |
| fast | https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/main/Qwen3.5-9B-Q4_K_M.gguf | 同仓库 mmproj-F16.gguf |

备用发布者：以 `config/models.manifest` 当前 URL 为准；不要在脚本或文档中另行维护模型 pin。
断点续传坑（302 → CDN Range 探测）已封装在 `lm deploy` 内，手动 curl 见 `scripts/deploy.sh` 的 `download_gguf()` 注释。

### 导入

```bash
lm import qwen3.8-main-q4 ~/models/gguf/Qwen3.8-27B-Q4_K_M.gguf 65536
lm run qwen3.8-main-q4
```

- `ollama create` 会把权重复制进 `~/models/ollama/`，导入完成后 `~/models/gguf/` 里的副本可删（或留作备份）。
- **mmproj 说明**：官方 `ollama pull` 的 tag 已内置视觉，无需额外文件；仅手动 GGUF 导入需要同仓库 `mmproj-*.gguf`（LM Studio 同目录放齐；Ollama Modelfile 双 FROM，以当前文档为准）。
- 手动导入的本地名与官方 tag 不同，功能等价即可；Cursor 模型名填 `create` 时的名字。

### 导入后回写

```bash
lm sync    # ollama list 回写 docs/models-registry.md
# 手动追加 docs/changelog.md；Cursor 默认模型变了 → 改 docs/agent-integration.md
```
