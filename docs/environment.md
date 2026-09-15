# 环境：硬件与运行时栈

采集日期：2026-07-20（v2.3 路径更新 2026-07-22）

选型与多机型清单初始化见 [hardware-profiles.md](./hardware-profiles.md)（`lm init`），不要把方案写死成仅 M5 Max。下面是**本仓库开发机**快照。

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
| LLM 主引擎 | **Ollama 0.33.0**（`lm deploy` / `lm upgrade-ollama` 对照 GitHub latest；未安装或落后均可自动装到 `/opt/homebrew/opt/ollama-upstream`） | 各档 LLM / OpenAI 兼容 API |
| 文生图引擎 | **mflux**（`uv tool install mflux`） | FLUX.2 Klein / Z-Image-Turbo（MLX CLI） |
| 辅 | **LM Studio 0.4.19+2** | GUI、手动 GGUF 加载 |
| 可选 | `mlx-lm` | 仅 LoRA / 脚本批处理 |

推荐环境变量（本机写在 `~/Library/LaunchAgents/homebrew.mxcl.ollama.plist` 的 `EnvironmentVariables`）：

```bash
export OLLAMA_FLASH_ATTENTION=1
export OLLAMA_KV_CACHE_TYPE=q8_0
```

守护进程**默认登录不自启**（`RunAtLoad`/`KeepAlive=false`，笔记本省电）：`lm start` / `lm stop` 按需启停，
`lm run` / `lm deploy` 自动拉起，`lm autostart on` 恢复常驻自启。

### 上下文长度的真实生效路径（易踩）

`config/models.manifest` 的 `NUM_CTX` **只作用于手动 GGUF 导入**（写进 Modelfile 的
`PARAMETER num_ctx`）。走 `ollama pull` 装的官方 tag **不带** `num_ctx`，实际服务上下文由
daemon 决定：

| 来源 | 优先级 | 说明 |
|------|--------|------|
| 请求里的 `options.num_ctx` | 最高 | 客户端可控；Cursor 等 OpenAI 兼容客户端**不会**发 |
| `OLLAMA_CONTEXT_LENGTH`（daemon 环境变量） | 中 | 全局默认；本机**未设置** |
| Ollama 内置默认 | 兜底 | 当前 0.32.x 为 **32768** |

因此本机 main / deep / fast 经 API 调用时实际都是 **32K**（`ollama ps` 的 CONTEXT 列可验证），
而非 manifest 里 main 那行的 65536。要真正改变：

```bash
ollama ps   # 确认当前实际 CONTEXT
# 全局抬高（会同时作用于 deep：30GB 权重 + 64K KV 逼近 48GB 上限，谨慎）
# 在 LaunchAgent 的 EnvironmentVariables 里加 OLLAMA_CONTEXT_LENGTH
# 单次调用抬高（推荐）
curl http://127.0.0.1:11434/api/chat -d '{"model":"qwen3.8:27b-q4_K_M","options":{"num_ctx":65536},...}'
```

## API 与路径

- OpenAI 兼容 API：`http://127.0.0.1:11434/v1`
- 权重统一目录：`~/models/`（ollama/ gguf/ image-gen/；`~/.ollama/models` 是 symlink）
