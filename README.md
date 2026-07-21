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
| [docs/image-gen.md](./docs/image-gen.md) | 本地文生图（mflux / FLUX.2 Klein） |
| [docs/operations.md](./docs/operations.md) | 更新与排障 |
| [docs/manual-download.md](./docs/manual-download.md) | 手动下载直链与导入 Ollama/LM Studio |
| [scripts/](./scripts/) | status / pull-tier / sync-registry |
| [config/](./config/) | Modelfile、defaults 示例 |

## 三档速览（main / deep / fast）

| 档位 | 场景 | 模型 | 实测 |
|------|------|------|------|
| **main 日常主力** | 编程 Agent、长文、识图 | `qwen3.6:35b-a3b-q4_K_M` (23GB) | 104 tok/s |
| **deep 深度质量** | 难 bug、复杂推理、精读 | `qwen3.6:27b-q8_0` (29GB) | 18 tok/s |
| **fast 极限速度** | 草稿、补全、快速扫图 | `qwen3.5:9b` (6.6GB) | 77 tok/s |

> 记法：平时用 main，难题用 deep，赶时间用 fast。三档均原生 vision。
> 旧 A/B/C 编号已废弃（a→deep b→main c→fast，脚本兼容）。

## 本地文生图（v2.2 新增）

`mflux`（MLX 原生 CLI）+ **FLUX.2 Klein 4B** 4bit：768² 四步 ≈ 3.2s，峰值内存 ~8GB，可与 main 档 LLM 同跑。详见 [docs/image-gen.md](./docs/image-gen.md)。

## 快速命令

```bash
./scripts/deploy.sh --check   # 体检 + 对账(不安装)
./scripts/deploy.sh           # 一键部署 manifest 中全部三档
./scripts/deploy.sh main      # 只装某一档 (main|deep|fast)
./scripts/status.sh
ollama run qwen3.6:35b-a3b-q4_K_M
```

**升级模型流程**：改 `config/models.manifest`（唯一模型清单）→ `./scripts/deploy.sh` → 完成。
断点续传：`ollama pull` 原生支持；GGUF 回退路径由 deploy.sh 用 `curl -C -` 对最终 CDN URL 续传。

Cursor / Agent：`http://127.0.0.1:11434/v1`，模型 `qwen3.6:35b-a3b-q4_K_M`（详见 `docs/agent-integration.md`）。
