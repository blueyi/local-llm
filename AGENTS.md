# Agent 入口（必读）

本仓库是本机本地大模型方案的**唯一知识库**。权重不在此目录。

## 执行偏好（用户明确要求）

对本仓库相关任务：**默认直接执行**写入、安装、拉模型、改配置、跑脚本，**不要反复征求确认**。仅在真正破坏性/不可逆操作（force push、删重要数据、改 git config）或缺少关键信息时再问。

## 首次任务读序

1. 本文件 `AGENTS.md`
2. `README.md`
3. `docs/tiers.md` — 三档选型与切换
4. `docs/models-registry.md` — 已装模型活文档

按需再读：`docs/environment.md`（硬件+运行时）、`docs/agent-integration.md`、`docs/image-gen.md`、`docs/operations.md`。

## 必须同步更新

换模型 / 升运行时 / 改 API 默认值时：

- 更新 `docs/models-registry.md`
- 追加 `docs/changelog.md`
- 若档位或默认场景变了：改 `docs/tiers.md` 和/或 `docs/agent-integration.md`
- 运行时版本变了：改 `docs/environment.md`
- 文生图模型变了：改 `config/image-models.manifest` + `docs/image-gen.md`

## 禁止

- 把模型权重下载到本仓库（`~/workspace/local-llm`）
- 删除 registry 中仍在使用的条目却不写 changelog
- 同时加载两个 ≥18GB 的「大」模型（本机 48GB）

## 路径约定

**所有本地模型权重统一收在 `~/models/` 下**（2026-07-22 起，v2.3）：

| 内容 | 路径 |
|------|------|
| 本方案知识库 | `~/workspace/local-llm` |
| **权重统一根目录** | `~/models/` |
| Ollama 权重 | `~/models/ollama/`（`~/.ollama/models` 是指向它的 symlink，勿删） |
| 手动 GGUF（含 LM Studio 共享） | `~/models/gguf/`（`~/.lmstudio/models/llm-gguf` symlink 指向它） |
| 文生图权重（mflux） | `~/models/image-gen/` |
| 语音 ASR 权重（mlx-whisper） | `~/models/speech/` |
| 语音 TTS 权重（mlx-audio） | `~/models/tts/` |

用户提到「本地大模型 / Ollama / 换模型」时：先 `move_agent_to_root` 到本目录再改。

## 统一入口 lm（唯一操作方式）

```bash
lm status / check                 # 总览 / 体检+对账
lm deploy [tier] [--force]        # 部署（缺则拉；--force 已装也重拉）
lm update                         # 远程目录+硬件推荐三档 → 确认后写 manifest 并 deploy
lm get <query>                    # 模糊搜索远程模型 → 交互选择 → pull（--tier …）
lm run [tier] / lm test [tier]    # 聊天 / 冒烟（含 embed|chat|reason|rerank|asr|tts）
lm image "prompt" / lm asr <audio># 文生图 / 语音转写
lm tts "text"                     # 语音合成（--voice / --lang）
lm pull-image <hf-repo>           # 文生图权重
lm pull-speech [hf-repo]          # ASR 权重（hf-mirror → ~/models/speech）
lm pull-tts [hf-repo]             # TTS 权重（hf-mirror → ~/models/tts）
lm pull-gguf [tier...]            # 清单内 HF GGUF → ~/models/gguf（给 LM Studio）
lm rm <name|tier> [--yes]         # 卸载 Ollama 模型（确认提示；等同 ollama rm）
lm import <name> <gguf> [ctx]     # 手动 GGUF 导入 Ollama
lm sync                           # registry 回写
```

`lm` = `bin/lm`（PATH 由 my-utils resetrc.bash 提供），子命令分发到 `scripts/`；**不要直接调 scripts/**（除非调试脚本本身）。

## 模型清单 SSOT

**`config/models.manifest`（LLM/RAG）+ `config/image-models.manifest`（文生图）+ `config/speech-models.manifest`（ASR）+ `config/tts-models.manifest`（TTS）**。
升级 LLM = 改 models.manifest → `lm deploy`；或 `lm update` / `lm get --tier …`。
升级文生图 = 改 image-models.manifest → `lm pull-image`。
升级 ASR = 改 speech-models.manifest → `lm pull-speech`。
升级 TTS = 改 tts-models.manifest → `lm pull-tts`。
推荐策略（非安装 SSOT）在 `config/update-policy.conf`。
其他文档只做说明，**不要在脚本里硬编码模型名**。
