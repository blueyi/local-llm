# 本地大模型方案（M5 Max / 48GB）

本机 Apple Silicon 本地 LLM 知识库：选型、安装、三档模型、Agent 对接与运维。

**不要**把权重放进本目录；权重由 Ollama / LM Studio 管理。

## 目录地图

| 路径 | 用途 |
|------|------|
| [AGENTS.md](./AGENTS.md) | Agent 必读入口 |
| [docs/hardware.md](./docs/hardware.md) | 硬件与内存法则 |
| [docs/stack.md](./docs/stack.md) | 运行时与版本 |
| [docs/tiers.md](./docs/tiers.md) | 三档矩阵与切换 |
| [docs/install.md](./docs/install.md) | 可复现安装步骤 |
| [docs/models-registry.md](./docs/models-registry.md) | 已装模型登记 |
| [docs/agent-integration.md](./docs/agent-integration.md) | Cursor / Agent API |
| [docs/operations.md](./docs/operations.md) | 更新与排障 |
| [docs/manual-download.md](./docs/manual-download.md) | 手动下载直链与导入 Ollama/LM Studio |
| [scripts/](./scripts/) | status / pull-tier / sync-registry |
| [config/](./config/) | Modelfile、defaults 示例 |

## 三档速览

| 档位 | 场景 | 默认方向 |
|------|------|----------|
| **A 最高质量** | 难 bug、复杂推理、精读 | `qwen3.6:27b-q8_0`（稠密）；上下文偏短 |
| **B 平衡（日常默认）** | 编程 Agent、长文、识图 | `qwen3.6:35b-a3b-q4_K_M`（全能，原生 vision） |
| **C 极限速度** | 草稿、补全、快速扫图 | `qwen3.5:9b`（原生 vision） |

> 2026-07-21 方案 v2：Qwen3.6/3.5 原生多模态，一个模型同时覆盖文本+识图；
> `qwen3-coder` / 独立 `qwen3-vl` 线退役（见 `docs/changelog.md`）。

## 快速命令

```bash
./scripts/status.sh
./scripts/pull-tier.sh b
ollama run qwen3.6:35b-a3b-q4_K_M
```

Cursor / Agent：`http://127.0.0.1:11434/v1`，模型 `qwen3.6:35b-a3b-q4_K_M`（详见 `docs/agent-integration.md`）。
