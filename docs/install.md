# 安装步骤（可复现）

## 1. 本知识库

```bash
# 已定路径
cd ~/workspace/local-llm
```

## 2. Ollama

```bash
brew install ollama
# 或：https://ollama.com/download
ollama --version   # 建议 ≥ 0.19（Apple Silicon MLX）
```

服务一般会自动启动；也可手动：

```bash
ollama serve
```

按档拉取：

```bash
./scripts/pull-tier.sh b   # 平衡（默认先装）
./scripts/pull-tier.sh a   # 高质量（体积大）
./scripts/pull-tier.sh c   # 速度
```

## 3. LM Studio

1. 安装：https://lmstudio.ai （macOS Apple Silicon）
2. 设置中选择 **MLX** 引擎
3. 下载 VL：`Qwen3-VL-30B-A3B` 4-bit（B）；需要时再下 6-bit（A）与小杯 VL（C）
4. 可选：开启 Local Server（OpenAI 兼容）

## 4. 安装后回写

- `docs/stack.md` — 版本号
- `docs/models-registry.md` — 已装清单（或跑 `./scripts/sync-registry.sh`）
- `docs/changelog.md` — 记一笔
