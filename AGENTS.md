# Agent 入口（必读）

本仓库是本机本地大模型方案的**唯一知识库**。权重不在此目录。

## 执行偏好（用户明确要求）

对本仓库相关任务：**默认直接执行**写入、安装、拉模型、改配置、跑脚本，**不要反复征求确认**。仅在真正破坏性/不可逆操作（force push、删重要数据、改 git config）或缺少关键信息时再问。

## 首次任务读序

1. 本文件 `AGENTS.md`
2. `README.md`
3. `docs/tiers.md` — 三档选型与切换
4. `docs/models-registry.md` — 已装模型活文档

按需再读：`docs/hardware.md`、`docs/stack.md`、`docs/agent-integration.md`、`docs/operations.md`。

## 必须同步更新

换模型 / 升运行时 / 改 API 默认值时：

- 更新 `docs/models-registry.md`
- 追加 `docs/changelog.md`
- 若档位或默认场景变了：改 `docs/tiers.md` 和/或 `docs/agent-integration.md`
- 运行时版本变了：改 `docs/stack.md`

## 禁止

- 把模型权重下载到本仓库（`~/workspace/local-llm`）
- 删除 registry 中仍在使用的条目却不写 changelog
- 同时加载两个 ≥18GB 的「大」模型（本机 48GB）

## 路径约定

| 内容 | 路径 |
|------|------|
| 本方案知识库 | `~/workspace/local-llm` |
| Ollama 权重 | `~/.ollama/` |
| LM Studio 权重 | 见应用设置（常见 `~/.lmstudio/models`） |

用户提到「本地大模型 / Ollama / 换模型」时：先 `move_agent_to_root` 到本目录再改。

## 快捷脚本

```bash
./scripts/deploy.sh --check   # 体检+对账
./scripts/deploy.sh           # 一键部署（读 config/models.manifest，断点续传）
./scripts/deploy.sh --prune   # 部署并清理 retired 模型
./scripts/status.sh
./scripts/sync-registry.sh
./scripts/import-gguf.sh <name> ~/Downloads/llm-gguf/xxx.gguf
```

## 模型清单 SSOT

**`config/models.manifest` 是唯一模型清单**（档位、tag、ctx、GGUF 回退直链）。
升级模型 = 改 manifest → `./scripts/deploy.sh`。
其他文档（tiers.md / registry / defaults.env）只做说明，**不要在脚本里硬编码模型名**。
`pull-tier.sh` 已由 deploy.sh 取代（保留兼容）。
