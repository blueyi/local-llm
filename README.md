# 本地大模型方案（M5 Max / 48GB）

本机 Apple Silicon 的**本地模型一站式工程**：三档 LLM（Ollama）+ 本地文生图（mflux），
统一命令行入口 `lm`，manifest 驱动的可复现部署，Agent（Cursor / Hermes）无缝对接。

**权重不进本仓库** —— 所有权重统一在 `~/models/`：

```text
~/models/
├── ollama/      # LLM / embed / rerank / chat / reason（~/.ollama/models → symlink）
├── image-gen/   # 文生图（FLUX.2 Klein / Z-Image-Turbo）
├── speech/      # ASR（mlx-whisper）
├── tts/         # TTS（mlx-audio / Kokoro）
└── gguf/        # 手动 GGUF（~/.lmstudio/models/llm-gguf → symlink）
```

## 统一入口：`lm`

一切操作从 `lm` 走（`bin/lm`，由 my-utils `config/resetrc.bash` 加入 PATH）：

```bash
# —— 日常 ——
lm status                    # 总览：权重目录/symlink 健康/已装模型/mflux/磁盘
lm run                       # 和 main 档聊天（lm run deep / fast / <任意tag>）
lm test fast                 # 冒烟 + tok/s
lm image "a cute kitten"     # 文生图（3~8s 出图，全离线）

# —— 部署 / 升级 ——
lm check                     # 体检 + manifest 对账（不安装）
lm deploy                    # 按 manifest 部署（先检查 Ollama 是否最新；缺则拉）
lm deploy --force            # 已装也强制重拉
lm deploy --yes              # Ollama 落后时不询问，直接升级再部署
lm upgrade-ollama            # 单独升级运行时到 GitHub latest
lm update                    # 远程最新 + 本机硬件 → 推荐三档，确认后更新并 deploy
lm get <query>               # 模糊搜索远程模型，交互选择后下载（可 --tier 写入清单）
lm pull-image <hf-repo>      # 下载文生图权重（hf-mirror 直拉）

# —— 维护 ——
lm rm <name|tier>            # 卸载 Ollama 模型（确认提示；可用档位名）
lm import <name> <gguf> [ctx]  # 手动 GGUF 导入 Ollama
lm sync                        # ollama list 回写 registry
```

首次安装（新机器）见 [docs/install.md](./docs/install.md)。

## LLM / RAG / 推理角色

| 角色 | 场景 | 模型 | 约大小 |
|------|------|------|--------|
| **main** | 编程 Agent、长文、识图 | `qwen3.8:27b-q4_K_M` | 18GB |
| **deep** | 难 bug、精读 | `qwen3.8:27b-q8_0` | 30GB |
| **fast** | 草稿、补全 | `qwen3.5:9b` | 6.6GB |
| **embed** | RAG 检索 | `qwen3-embedding:8b` | 4.7GB |
| **rerank** | RAG 重排 | `awenleven/Qwen3-Reranker-4B:Q4_K_M` | 2.5GB |
| **chat** | 闲聊、创意（非 Agent） | `gemma4:31b` | 20GB |
| **reason** | 专用推理 | `gpt-oss:20b` | ~14GB |

语音：ASR `lm asr audio.wav`；TTS 日常 `lm tts "你好"`（Kokoro），质量档 `lm tts "…" --model qwen3-tts-1.7b`（Qwen3-TTS 1.7B）。详见 [docs/tiers.md](./docs/tiers.md)。

```bash
lm deploy                    # 拉取 models.manifest 全部角色
lm pull-speech               # ASR 权重
lm pull-tts                  # TTS 权重
lm pull-gguf main deep fast --link   # Unsloth GGUF → ~/models/gguf（LM Studio）
lm test reason && lm test rerank && lm test asr && lm test tts
```

## 本地文生图

引擎 **mflux**（MLX 原生），双模型，峰值 ~6-8GB **可与 main 档 LLM 同跑**：

| 模型 | 风格 | 速度 | 改图 |
|------|------|------|------|
| **FLUX.2 Klein 4B**（默认） | 通用/插画/概念图 | 768² ×4步 ≈ 3.2s | ✅ `--edit` |
| Z-Image-Turbo | 写实/人像 | 768² ×9步 ≈ 9.3s | ❌ |

```bash
lm image "A cute orange kitten wearing tiny glasses"           # 默认 Klein，768²
lm image --model z-image-turbo "portrait, golden hour light"   # 写实向
lm image --size 1024x576 --steps 6 --seed 42 "..."             # 精细控制
lm image --edit photo.png "make the sky sunset orange" out.png # 改图
```

**升级/换模型** = 改 [`config/image-models.manifest`](./config/image-models.manifest) → `lm pull-image <新repo>`。
详见 [docs/image-gen.md](./docs/image-gen.md)。

## Agent 对接

| Agent | 方式 |
|-------|------|
| **Cursor / 任意 OpenAI 客户端** | Base URL `http://127.0.0.1:11434/v1`，模型 `qwen3.8:27b-q4_K_M`（[docs/agent-integration.md](./docs/agent-integration.md)） |
| **Hermes 对话出图** | `image_generate` 已接本地 mflux（user plugin），直接说"画一张…"即可；改图给图+指令。切模型：`hermes config set image_gen.model z-image-turbo` |
| **Hermes 本地 LLM 兜底** | `local-ollama` provider 已注册为 fallback |

## 目录地图

```text
bin/lm                          # ← 统一 CLI 入口（唯一需要记住的命令）
config/models.manifest          # LLM/RAG/推理角色清单（SSOT）
config/image-models.manifest    # 文生图模型清单（SSOT）
config/speech-models.manifest   # ASR 模型清单（SSOT）
config/tts-models.manifest      # TTS 模型清单（SSOT）
config/update-policy.conf        # lm update / lm get 的推荐策略（非安装 SSOT）
scripts/                        # lm 各子命令的实现（不直接调用）
docs/
├── environment.md              # 硬件、内存法则、运行时栈、API
├── install.md                  # 新机安装 + 手动 GGUF 下载/导入回退
├── tiers.md                    # 三档选型依据与候选评估记录
├── image-gen.md                # 文生图：选型/用法/坑/Hermes 集成
├── agent-integration.md        # Cursor / Agent API 对接
├── models-registry.md          # 已装模型登记（lm sync 自动回写）
├── operations.md               # 日常运维与排障
└── changelog.md                # 全部变更历史
integrations/hermes-mflux-plugin/  # Hermes 插件源码备份（部署在 ~/.hermes/plugins/）
```

## 设计原则

1. **SSOT**：模型清单只存在于 `config/*.manifest`，脚本/文档不硬编码模型名。
2. **权重与知识库分离**：仓库只有文本；权重统一 `~/models/`，靠 symlink 兼容各工具默认路径。
3. **可重入**：`lm deploy` 幂等，断点续传（ollama 原生 / curl 对 CDN 最终 URL 续传）。
4. **改清单即升级**：换模型不改代码，改 manifest 一行 → `lm deploy` / `lm pull-image`；或用 `lm update` / `lm get` 自动发现后写入清单。
5. **更新前确认**：`lm update` / `lm get` 默认交互确认；硬件未指定时自动探测本机。
