# 三档模型矩阵

统一以 **Qwen3.6 / Qwen3.5 系** 为主（原生多模态，一个模型覆盖文本+识图）。精确 tag 以 [models-registry.md](./models-registry.md) 为准。

> 2026-07-21 方案升级：`qwen3-coder`（Qwen3 一代）与独立 `qwen3-vl` 线全部退役。
> Qwen3.6-35B-A3B 在 SWE-bench Verified（73.4%）与 Terminal-Bench 2.0（51.5%）上
> 反超同级编码专用模型（Laguna XS 2.1 / North Mini Code / GLM-4.7-Flash），且原生支持图像输入。

## B — 平衡（日常默认，Q4_K_M）

| 场景 | 模型 | 大小 | 建议上下文 |
|------|------|------|------------|
| 编程 / Agent / 通用 / 识图（全能主力） | `qwen3.6:35b-a3b-q4_K_M` | 24GB | 32K–64K |
| 同上，解码更快（MTP 多 token 预测） | `qwen3.6:35b-a3b-mtp-q4_K_M` | 23GB | 32K–64K |
| 同上，Apple Silicon MLX 引擎 | `qwen3.6:35b-mlx` | 22GB | 32K–64K |

三者同源同权重，**装一个即可**（默认 q4_K_M；追求解码速度可换 mtp 或 mlx 变体，实测后二选一）。

原则：一天常驻一个 B 档模型；识图无需切换（原生 vision）。

## A — 最高质量

| 场景 | 模型 | 大小 | 建议上下文 |
|------|------|------|------------|
| 难 bug / 精读 / 复杂推理 | `qwen3.6:27b-q8_0`（稠密 27B） | 30GB | 16K–32K |
| 备选：35B-A3B 中间量化 | unsloth `Qwen3.6-35B-A3B-UD-Q6_K.gguf` 手动导入 | 29GB | 16K–32K |

⚠️ 不再推荐 `qwen3.6:35b-a3b-q8_0`：实际 **39GB**，超出 34–38GB 内存预算，上下文会被挤死。

## C — 极限速度

| 场景 | 模型 | 大小 | 建议上下文 |
|------|------|------|------------|
| 草稿 / 补全 / 快速扫图 | `qwen3.5:9b` | 6.6GB | 8K–32K |

一个模型同时覆盖原 `qwen3:8b`（草稿）+ `qwen3-vl:8b`（扫图）两个位置。

## 观察名单（暂不进档）

| 模型 | 理由 |
|------|------|
| `ornith:35b`（21GB, MIT） | 3 周前发布，宣称同级 agentic coding SOTA（Terminal-Bench 2.1 / SWE-Bench），可作编码专项 A/B 试验 |
| `laguna-xs-2.1`（20GB） | 官方页面明示 **macOS 已知问题调查中**，修复后再评估 |
| `glm-4.7-flash`（19GB） | SWE-bench 59.2 低于 Qwen3.6；纯文本、198K 上下文 |

## 切换工作流

| 你在做什么 | 档位 | 模型 |
|------------|------|------|
| 日常写代码、Cursor Agent、识图 | B | `qwen3.6:35b-a3b-q4_K_M` |
| 难 bug / 架构 / 精读长文 | A | `qwen3.6:27b-q8_0` |
| 补全、起草稿、快速扫图 | C | `qwen3.5:9b` |

```bash
./scripts/pull-tier.sh b   # 或 a / c
ollama run qwen3.6:35b-a3b-q4_K_M
```
