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

用户提到「本地大模型 / Ollama / 换模型」时：先 `move_agent_to_root` 到本目录再改。

## 统一入口 lm（唯一操作方式）

```bash
lm status / check                 # 总览 / 体检+对账
lm deploy [main|deep|fast]        # 一键部署（读 config/models.manifest，断点续传；--prune 清 retired）
lm run [tier] / lm test [tier]    # 聊天 / 冒烟+tok/s
lm image "prompt"                 # 文生图（--model --size --steps --seed --edit）
lm pull-image <hf-repo>           # 文生图权重下载（hf-mirror 直拉）
lm import <name> <gguf> [ctx]     # 手动 GGUF 导入
lm sync                           # registry 回写
```

`lm` = `bin/lm`（symlink 在 `~/.local/bin/lm`），子命令分发到 `scripts/`；**不要直接调 scripts/**（除非调试脚本本身）。

## 模型清单 SSOT

**`config/models.manifest`（LLM）+ `config/image-models.manifest`（文生图）是唯二模型清单**。
升级 LLM = 改 models.manifest → `lm deploy`；升级文生图 = 改 image-models.manifest → `lm pull-image`。
其他文档（tiers.md / registry / defaults.env）只做说明，**不要在脚本里硬编码模型名**。
