# 本地大模型方案（M5 Max / 48GB）

本机 Apple Silicon 的**本地模型一站式工程**：三档 LLM（Ollama）+ 本地文生图（mflux），
统一命令行入口 `lm`，manifest 驱动的可复现部署，Agent（Cursor / Hermes）无缝对接。

**权重不进本仓库** —— 所有权重统一在 `~/models/`：

```text
~/models/
├── ollama/      # 三档 LLM 权重（~/.ollama/models 是指向它的 symlink，勿删）
├── image-gen/   # 文生图权重（FLUX.2 Klein / Z-Image-Turbo）
└── gguf/        # 手动下载的 GGUF（~/.lmstudio/models/llm-gguf symlink 指向它）
```

## 统一入口：`lm`

一切操作从 `lm` 走（`bin/lm`，已 symlink 到 `~/.local/bin/lm`）：

```bash
# —— 日常 ——
lm status                    # 总览：权重目录/symlink 健康/已装模型/mflux/磁盘
lm run                       # 和 main 档聊天（lm run deep / fast / <任意tag>）
lm test fast                 # 冒烟 + tok/s
lm image "a cute kitten"     # 文生图（3~8s 出图，全离线）

# —— 部署 / 升级 ——
lm check                     # 体检 + manifest 对账（不安装）
lm deploy                    # 按 manifest 部署全部三档（断点续传，可重入）
lm pull-image <hf-repo>      # 下载文生图权重（hf-mirror 直拉）

# —— 维护 ——
lm import <name> <gguf> [ctx]  # 手动 GGUF 导入 Ollama
lm sync                        # ollama list 回写 registry
```

首次安装（新机器）见 [docs/install.md](./docs/install.md)。

## 三档 LLM（main / deep / fast）

| 档位 | 场景 | 模型 | 实测 |
|------|------|------|------|
| **main 日常主力** | 编程 Agent、长文、识图 | `qwen3.6:35b-a3b-q4_K_M` (23GB) | 104 tok/s |
| **deep 深度质量** | 难 bug、复杂推理、精读 | `qwen3.6:27b-q8_0` (29GB) | 18 tok/s |
| **fast 极限速度** | 草稿、补全、快速扫图 | `qwen3.5:9b` (6.6GB) | 77 tok/s |

> 记法：平时用 main，难题用 deep，赶时间用 fast。三档均**原生 vision**。
> 48GB 法则：同时只加载一个 ≥18GB 大模型（详见 [docs/environment.md](./docs/environment.md)）。

**升级/换模型** = 改 [`config/models.manifest`](./config/models.manifest)（唯一清单）→ `lm deploy` → 完成。

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
| **Cursor / 任意 OpenAI 客户端** | Base URL `http://127.0.0.1:11434/v1`，模型 `qwen3.6:35b-a3b-q4_K_M`（[docs/agent-integration.md](./docs/agent-integration.md)） |
| **Hermes 对话出图** | `image_generate` 已接本地 mflux（user plugin），直接说"画一张…"即可；改图给图+指令。切模型：`hermes config set image_gen.model z-image-turbo` |
| **Hermes 本地 LLM 兜底** | `local-ollama` provider 已注册为 fallback |

## 目录地图

```text
bin/lm                          # ← 统一 CLI 入口（唯一需要记住的命令）
config/models.manifest          # LLM 三档清单（SSOT）
config/image-models.manifest    # 文生图模型清单（SSOT）
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
4. **改清单即升级**：换模型不改代码，改 manifest 一行 → `lm deploy` / `lm pull-image`。
