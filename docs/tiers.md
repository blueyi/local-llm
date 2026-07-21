# 三档模型矩阵

统一以 **Qwen3.6 / Qwen3.5 系** 为主（原生多模态，一个模型覆盖文本+识图）。
**安装依据是 `config/models.manifest`（SSOT）**，本文只做说明。

## 档位命名（v2.1，按用途取名）

| 档位 | 记法 | 模型 | 大小 | 实测速度 | 建议上下文 |
|------|------|------|------|----------|------------|
| **main** | 平时用 | `qwen3.6:35b-a3b-q4_K_M` | 23GB | 104 tok/s | 32K–64K |
| **deep** | 难题用 | `qwen3.6:27b-q8_0`（稠密） | 29GB | 18 tok/s | 16K–32K |
| **fast** | 赶时间 | `qwen3.5:9b` | 6.6GB | 77 tok/s | 8K–32K |

（旧 A/B/C 编号已废弃：a→deep，b→main，c→fast，脚本仍兼容）

## 场景切换

| 你在做什么 | 档位 | 模型 |
|------------|------|------|
| 日常写代码、Cursor Agent、识图、长文 | main | `qwen3.6:35b-a3b-q4_K_M` |
| 难 bug / 架构推演 / 精读（慢而准） | deep | `qwen3.6:27b-q8_0` |
| 补全、草稿、快问快答、快速扫图 | fast | `qwen3.5:9b` |

```bash
./scripts/deploy.sh --check
ollama run qwen3.6:35b-a3b-q4_K_M
```

原则：一次只常驻一个大模型（main/deep 二选一）；识图无需切换（三档均原生 vision）。

## 选型依据（2026-07 复核，全球范围）

编码/Agent 是本机主用途，以 SWE-bench Verified / Terminal-Bench 为主标尺：

| 模型 | SWE-bench V | 结论 |
|------|-------------|------|
| **Qwen3.6-35B-A3B** | **73.4%** | ✅ main：同级第一，且原生多模态 |
| Laguna XS 2.1 (33B) | 70.9% | macOS 官方已知问题未修 |
| North Mini Code (30B) | 67.6% | 弱于 Qwen3.6，纯文本 |
| GLM-4.7-Flash (30B) | 59.2% | 弱于 Qwen3.6，纯文本 |
| **Gemma 4 26B-A4B** | **17.4%** | ❌ 编码/Agent 差距悬殊（见下） |

### 为什么不用 Gemma 4

明确评估过，不适合本机的主用途：

- **编码硬伤**：SWE-bench Verified 17.4 vs 73.4（差 56 分）；MCP 工具调用得分约为 Qwen3.6 一半；社区报告 vLLM/Ollama 下 tool-call 格式需额外 JSON 修补、多轮生成有 bug（2026-04 实测汇总，grigio.org）
- **Arena 强是「聊天偏好」信号**：Gemma 4 31B Arena ELO #3 名列前茅，但那衡量对话讨喜度，不是 agentic 工程能力
- **它赢的维度本机用不上/已覆盖**：多语言客服、创意写作、视频理解、edge 端部署
- 若未来需要「聊天/创意/日文西文」专用模型，可考虑 `gemma4:26b`（18GB）进 watch 名单，不占三档

## 观察名单（暂不进档）

| 模型 | 理由 |
|------|------|
| `ornith:35b`（21GB, MIT） | 宣称同级 agentic coding SOTA（Terminal-Bench 2.1 / SWE-Bench），可作编码专项 A/B 试验 |
| `laguna-xs-2.1`（20GB） | 官方页面明示 macOS 已知问题调查中，修复后再评估 |
| `gemma4:26b`（18GB） | 聊天/创意/多语言备选，编码不行 |

## deep 档备选

不再推荐 `qwen3.6:35b-a3b-q8_0`：实际 39GB，超出 34–38GB 内存预算。
如需 MoE 速度 + 更高精度：unsloth `Qwen3.6-35B-A3B-UD-Q6_K.gguf`（29GB）手动导入。
