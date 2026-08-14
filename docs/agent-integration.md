# Cursor / Agent 对接

## Ollama（推荐）

| 项 | 值 |
|----|-----|
| Base URL | `http://127.0.0.1:11434/v1` |
| API Key | 任意非空（如 `ollama`） |
| **main 日常主力** | `qwen3.8:27b-q4_K_M` |
| deep 深度质量 | `qwen3.8:27b-q8_0` |
| fast 极限速度 | `qwen3.5:9b` |
| chat 闲聊/创意 | `gemma4:31b`（勿用于 Cursor Agent） |
| reason 专用推理 | `gpt-oss:20b` |
| embed RAG | `qwen3-embedding:8b`（`/api/embeddings`） |
| rerank RAG | `awenleven/Qwen3-Reranker-4B:Q4_K_M` |
| 识图 | main/deep/fast 任一（原生 vision，无需单独 VL） |
| 语音转写 | `lm asr <audio>`（非 OpenAI `/v1`，mlx-whisper） |
| 语音合成 | `lm tts "text"`（非 OpenAI `/v1`，mlx-audio / Kokoro） |

探测：

```bash
curl http://127.0.0.1:11434/api/tags
curl http://127.0.0.1:11434/v1/models
```

## 场景 → 模型

| 场景 | 档位 | 模型 |
|------|------|------|
| Cursor Agent / 日常编程 / 识图 | main | `qwen3.8:27b-q4_K_M` |
| 难 bug / 架构 / 精读 | deep | `qwen3.8:27b-q8_0` |
| 快速草稿 / 补全 / 扫图 | fast | `qwen3.5:9b` |
| 闲聊 / 多语言 / 创意 | chat | `gemma4:31b` |
| RAG / 语义检索 | embed | `qwen3-embedding:8b` |

> deep 档 27B 稠密 Q8（~30GB）：上下文控制在 **16K–32K**，不与其它大模型同开。
> main 档 ~18GB 可放心开 64K 上下文。

## 配置片段

见 [config/defaults.env.example](../config/defaults.env.example)。

## Hermes Agent（已接入）

`~/.hermes/config.yaml` 中已注册 `local-ollama` provider，并把 main/fast 档挂在 fallback 链末尾（云端全挂时自动降级到本地）：

```yaml
providers:
  local-ollama:
    base_url: http://127.0.0.1:11434/v1
    api_key: ollama
    models: [qwen3.8:27b-q4_K_M, qwen3.8:27b-q8_0, qwen3.5:9b]
fallback_providers:
  # ...云端条目...
  - {provider: local-ollama, model: qwen3.8:27b-q4_K_M}
  - {provider: local-ollama, model: qwen3.5:9b}
```

手动指定本地模型跑 Hermes：

```bash
hermes chat -q "..." -m qwen3.8:27b-q4_K_M --provider local-ollama
```

> 注意：Qwen thinking 系在 OpenAI 兼容接口下 reasoning 占用 completion tokens，
> 调用方 `max_tokens` 需 ≥2048，否则回复会被 thinking 吃光（finish=length，content 空）。
