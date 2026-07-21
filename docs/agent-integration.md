# Cursor / Agent 对接

## Ollama（推荐）

| 项 | 值 |
|----|-----|
| Base URL | `http://127.0.0.1:11434/v1` |
| API Key | 任意非空（如 `ollama`） |
| **B 全能主力（已装）** | `qwen3.6:35b-a3b-q4_K_M` |
| A 质量（待装） | `qwen3.6:27b-q8_0` |
| C 速度（待装） | `qwen3.5:9b` |
| 识图 | 同上任一（Qwen3.6/3.5 原生 vision，无需单独 VL 模型） |
| 过渡期备用 | `qwen3-coder:30b-a3b-q8_0`（验证新主力后退役） |

探测：

```bash
curl http://127.0.0.1:11434/api/tags
curl http://127.0.0.1:11434/v1/models
```

## 场景 → 模型

| 场景 | 档位 | 模型 |
|------|------|------|
| Cursor Agent / 日常编程 / 识图 | B | `qwen3.6:35b-a3b-q4_K_M` |
| 难 bug / 架构 / 精读 | A | `qwen3.6:27b-q8_0` |
| 快速草稿 / 补全 / 扫图 | C | `qwen3.5:9b` |

> A 档 27B 稠密 Q8（~30GB）：上下文控制在 **16K–32K**，不与其它大模型同开。
> B 档 24GB 可放心开 64K 上下文。

## 配置片段

见 [config/defaults.env.example](../config/defaults.env.example)。
