# Cursor / Agent 对接

> 本页按**当前提交的清单**（lite-16：M5 / 16GB）描述。其他机型经 `lm init` 生成不同角色集合，
> 以 `config/models.manifest` 为准；多机型 lineup 见 [hardware-profiles.md](./hardware-profiles.md)。

## Ollama（推荐）

| 项 | 值 |
|----|-----|
| Base URL | `http://127.0.0.1:11434/v1` |
| API Key | 任意非空（如 `ollama`） |
| **main 日常主力** | `qwen3.5:9b`（本机唯一 LLM 档；原生 vision，识图无需单独 VL） |
| embed RAG | `qwen3-embedding:4b`（`/api/embeddings`） |
| rerank RAG | `awenleven/Qwen3-Reranker-4B:Q4_K_M` |
| 语音转写 | `lm asr <audio>`（非 OpenAI `/v1`，mlx-whisper） |
| 语音合成 | `lm tts "text"`（非 OpenAI `/v1`，mlx-audio / Kokoro） |

> lite-16（16GB）**不设**独立 deep / fast / chat / reason / redteam 档——对话、编程、识图全部走 main。
> 大内存机型（std-36 及以上）才有 `qwen3.8:27b-q8_0`（deep）、`gemma4:31b`（chat）、
> `gpt-oss:20b`（reason）以及对齐攻防档 `redteam` / `redfast`（研究用，不接 Cursor），见 [tiers.md](./tiers.md)。

探测：

```bash
curl http://127.0.0.1:11434/api/tags
curl http://127.0.0.1:11434/v1/models
```

## 场景 → 模型

| 场景 | 档位 | 模型 |
|------|------|------|
| Cursor Agent / 日常编程 / 识图 | main | `qwen3.5:9b` |
| RAG / 语义检索 | embed | `qwen3-embedding:4b` |
| RAG 二阶段重排 | rerank | `awenleven/Qwen3-Reranker-4B:Q4_K_M` |

> **实际上下文 = 32K**（Ollama daemon 默认；`OLLAMA_CONTEXT_LENGTH` 本机未设置，
> Cursor 等客户端也不会发 `options.num_ctx`）。manifest 里的 `NUM_CTX` 只对
> 手动 GGUF 导入生效——见 [environment.md 上下文长度的真实生效路径](./environment.md#上下文长度的真实生效路径易踩)。

## 配置片段

见 [config/defaults.env.example](../config/defaults.env.example)。

## Hermes Agent（已接入）

`~/.hermes/config.yaml` 中已注册 `local-ollama` provider，并挂在 `fallback_providers`
链**末尾**（云端全挂时自动降级到本地）：

```yaml
providers:
  local-ollama:
    base_url: http://127.0.0.1:11434/v1
    api_key: ollama
    api_mode: chat_completions
    model: qwen3.5:9b
    default_model: qwen3.5:9b
    models: [qwen3.5:9b]
fallback_providers:
  # ...云端条目...
  - {provider: local-ollama, model: qwen3.5:9b}   # 本地兜底，最后才用
```

**前置条件（`lm` 侧只需一条）**：`lm deploy` —— 拉起 Ollama daemon 并按 manifest 拉齐权重
（新机更省事：`lm init --deploy` 一条完成依赖安装 + 清单 + 权重）。之后 Hermes 即可用，
无需再跑其他 `lm` 命令；日常可用 `lm status` / `lm check` 确认 daemon 与权重健康。

手动指定本地模型跑 Hermes：

```bash
hermes chat -q "..." -m qwen3.5:9b --provider local-ollama
```

> 注意：Qwen thinking 系在 OpenAI 兼容接口下 reasoning 占用 completion tokens，
> 调用方 `max_tokens` 需 ≥2048，否则回复会被 thinking 吃光（finish=length，content 空）。
> 16GB 机型上 Hermes 完整系统提示 + thinking 的首轮延迟约为分钟级，属正常现象。
