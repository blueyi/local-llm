# 环境：硬件与运行时栈

采集日期：2026-07-20（v2.3 路径更新 2026-07-22）

## 硬件快照

| 项目 | 规格 |
|------|------|
| 机型 | MacBook Pro (Mac17,6) |
| 芯片 | Apple **M5 Max** |
| CPU | 18 核（6 Super + 12 Performance） |
| GPU | **40** 核，Metal 4 |
| 统一内存 | **48 GB** LPDDR5 |
| 存储 | 2 TB SSD |
| 系统 | macOS 26.6 / arm64 |

### 可用内存法则

- 系统 + Cursor/IDE + 浏览器预留约 **10–12 GB**
- 模型权重 + KV cache 实用预算约 **34–38 GB**
- 同时只加载 **一个** ≥18GB 的大模型
- 「高质量」档优先提高量化精度，并**主动限制上下文**，不要硬开官方 256K
- 文生图（mflux）峰值 ~6–8GB，可与 main 档 LLM 同跑

### 甜点与禁区

- **甜点**：30–35B MoE（约 3B 激活）Q4–Q6；27B 稠密 Q6–Q8
- **不推荐常态**：70B+ 稠密（权重与上下文互相挤压，Agent 体验差）

## 运行时栈

| 角色 | 工具 | 用途 |
|------|------|------|
| LLM 主引擎 | **Ollama ≥0.32.12**（`lm deploy` / `lm upgrade-ollama` 对照 GitHub latest；落后可自动装到 `/opt/homebrew/opt/ollama-upstream`） | 各档 LLM / OpenAI 兼容 API |
| 文生图引擎 | **mflux**（`uv tool install mflux`） | FLUX.2 Klein / Z-Image-Turbo（MLX CLI） |
| 辅 | **LM Studio 0.4.19+2** | GUI、手动 GGUF 加载 |
| 可选 | `mlx-lm` | 仅 LoRA / 脚本批处理 |

推荐环境变量：

```bash
export OLLAMA_FLASH_ATTENTION=1
export OLLAMA_KV_CACHE_TYPE=q8_0
```

## API 与路径

- OpenAI 兼容 API：`http://127.0.0.1:11434/v1`
- 权重统一目录：`~/models/`（ollama/ gguf/ image-gen/；`~/.ollama/models` 是 symlink）
