# Cursor / Agent 对接

## Ollama（推荐）

| 项 | 值 |
|----|-----|
| Base URL | `http://127.0.0.1:11434/v1` |
| API Key | 任意非空（如 `ollama`） |
| **main 日常主力** | `qwen3.6:35b-a3b-q4_K_M` |
| deep 深度质量 | `qwen3.6:27b-q8_0` |
| fast 极限速度 | `qwen3.5:9b` |
| 识图 | 同上任一（Qwen3.6/3.5 原生 vision，无需单独 VL 模型） |

探测：

```bash
curl http://127.0.0.1:11434/api/tags
curl http://127.0.0.1:11434/v1/models
```

## 场景 → 模型

| 场景 | 档位 | 模型 |
|------|------|------|
| Cursor Agent / 日常编程 / 识图 | main | `qwen3.6:35b-a3b-q4_K_M` |
| 难 bug / 架构 / 精读 | deep | `qwen3.6:27b-q8_0` |
| 快速草稿 / 补全 / 扫图 | fast | `qwen3.5:9b` |

> deep 档 27B 稠密 Q8（29GB）：上下文控制在 **16K–32K**，不与其它大模型同开。
> main 档 23GB 可放心开 64K 上下文。

## 配置片段

见 [config/defaults.env.example](../config/defaults.env.example)。

## Hermes Agent（已接入）

`~/.hermes/config.yaml` 中已注册 `local-ollama` provider，并把 main/fast 档挂在 fallback 链末尾（云端全挂时自动降级到本地）：

```yaml
providers:
  local-ollama:
    base_url: http://127.0.0.1:11434/v1
    api_key: ollama
    models: [qwen3.6:35b-a3b-q4_K_M, qwen3.6:27b-q8_0, qwen3.5:9b]
fallback_providers:
  # ...云端条目...
  - {provider: local-ollama, model: qwen3.6:35b-a3b-q4_K_M}
  - {provider: local-ollama, model: qwen3.5:9b}
```

手动指定本地模型跑 Hermes：

```bash
hermes chat -q "..." -m qwen3.6:35b-a3b-q4_K_M --provider local-ollama
```

> 注意：Qwen3.6 thinking 系在 OpenAI 兼容接口下 reasoning 占用 completion tokens，
> 调用方 `max_tokens` 需 ≥2048，否则回复会被 thinking 吃光（finish=length，content 空）。
