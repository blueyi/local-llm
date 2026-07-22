# 手动下载与导入指南

Ollama 官方源较慢时，用下载工具从 Hugging Face 拉 **GGUF**，再导入 Ollama / LM Studio。

> 国内直连 `huggingface.co` 常不通，可将下面直链域名替换为 **`hf-mirror.com`**（已验证可达）。

**建议存放目录（权重，勿放进本仓库 git）：**

```text
~/models/gguf/
```

---

## 一、推荐下载清单（按档，2026-07-21 方案 v2）

下列为 **直链**（`resolve/main/...`）。若 404，打开对应「仓库页」在 Files 里点文件 → Copy download link。

### B — 平衡（全能主力，优先）

| 用途 | 约大小 | 仓库页 | 直链（GGUF） |
|------|--------|--------|----------------|
| 编程 / Agent / 通用 / 识图 | ~22 GB + mmproj | [unsloth Qwen3.6-35B-A3B GGUF](https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF) | 主模型：https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF/resolve/main/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf<br>视觉（识图需要）：https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF/resolve/main/mmproj-F16.gguf |

备用（同内容不同发布者）：
https://huggingface.co/bartowski/Qwen_Qwen3.6-35B-A3B-GGUF/resolve/main/Qwen_Qwen3.6-35B-A3B-Q4_K_M.gguf

### A — 最高质量

| 用途 | 约大小 | 直链示例 |
|------|--------|----------|
| 难 bug / 精读（稠密 27B Q8） | ~30 GB + mmproj | https://huggingface.co/unsloth/Qwen3.6-27B-GGUF/resolve/main/Qwen3.6-27B-Q8_0.gguf<br>视觉：https://huggingface.co/unsloth/Qwen3.6-27B-GGUF/resolve/main/mmproj-F16.gguf |
| A 档备选（35B MoE UD-Q6_K，更快） | ~29 GB | https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF/resolve/main/Qwen3.6-35B-A3B-UD-Q6_K.gguf |

### C — 极限速度

| 用途 | 约大小 | 直链 |
|------|--------|------|
| 草稿 / 补全 / 快扫图 | ~6.6 GB + mmproj | https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/main/Qwen3.5-9B-Q4_K_M.gguf<br>视觉：https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/main/mmproj-F16.gguf |

---

## 二、下载后如何处理

### 方式 1：导入 Ollama（推荐，对接 Cursor）

1. 确认文件完整（大小与页面标注接近，无 `.aria2` / `.download` 后缀）。
2. 为每个模型写一个 Modelfile（本仓库已预留目录）：

```bash
mkdir -p ~/workspace/local-llm/config/Modelfiles
# 示例：B 档全能主力
cat > ~/workspace/local-llm/config/Modelfiles/qwen36-b-q4 << 'EOF'
FROM /Users/yulong/models/gguf/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf
PARAMETER num_ctx 32768
EOF

ollama create qwen3.6-b-q4 -f ~/workspace/local-llm/config/Modelfiles/qwen36-b-q4
ollama run qwen3.6-b-q4
```

3. A / C 档同样改 `FROM` 路径与 `ollama create` 名称即可。
4. Cursor：Base URL `http://127.0.0.1:11434/v1`，模型名填你 `create` 时的名字（如 `qwen3.6-b-q4`）。

**注意：** `ollama create` 会把权重复制/登记进 `~/.ollama/`，完成后可删下载目录里的副本以省盘（或保留作备份）。

### 方式 2：LM Studio（GUI / 识图方便）

1. 打开 LM Studio → My Models → 把 `.gguf`（及 `mmproj`）放到它提示的 models 目录，或「Import」。
2. 引擎选 **MLX**（若该模型有 MLX 版）或 GGUF/llama.cpp。
3. Load 后可开 Local Server；纯 Agent 仍建议用 Ollama。

### 方式 3：多模态 mmproj 说明

- Qwen3.6 / Qwen3.5 为**原生多模态**：官方 Ollama tag（如 `qwen3.6:35b-a3b-q4_K_M`）已内置视觉能力，**直接 `ollama pull` 时无需任何额外文件**。
- 仅**手动 GGUF 导入**时需要同仓库的 `mmproj-*.gguf`：
  - LM Studio：同目录放主模型 + mmproj，加载时选齐。
  - Ollama Modelfile：`FROM ./model.gguf` 后再加一行 `FROM ./mmproj-F16.gguf`（以当前 `ollama` 文档为准）；不熟时优先用 LM Studio 跑图。

---

## 三、导入后请回写本知识库

```bash
~/workspace/local-llm/scripts/sync-registry.sh
# 并手动改 docs/models-registry.md 状态为 installed，追加 docs/changelog.md
```

把 Cursor 默认模型改成你 `ollama create` 的名字时，同步改 `docs/agent-integration.md` 与 `config/defaults.env.example`。

---

## 四、与官方 Ollama tag 的关系

| 本方案 Ollama tag | 手动 GGUF 等价 |
|---------------------|----------------|
| `qwen3.6:35b-a3b-q4_K_M` | Qwen3.6-35B-A3B UD-Q4_K_M.gguf + mmproj |
| `qwen3.6:27b-q8_0` | Qwen3.6-27B Q8_0.gguf + mmproj |
| `qwen3.5:9b` | Qwen3.5-9B Q4_K_M.gguf + mmproj |

功能等价即可，**名称不必与 Ollama 库完全一致**。
