# 本地模型场景矩阵与选型

当前已提交清单对齐 **M5 Max / 48GB**（`lm init` lineup `full-48`）。其他机型先 `lm init` 再看本页；安装依据：
- LLM/RAG：`config/models.manifest`
- 文生图：`config/image-models.manifest`
- 语音 ASR：`config/speech-models.manifest`
- 语音 TTS：`config/tts-models.manifest`

## 业界本地模型常用分类（2026-08）

| 分类 | 典型用途 | 本机方案 | 状态 |
|------|----------|----------|------|
| **Agentic coding** | Cursor/Agent、多文件改码 | **main** `qwen3.8:27b-q4_K_M` | ✅ |
| **Deep quality** | 难 bug、架构、精读 | **deep** `qwen3.8:27b-q8_0` | ✅ |
| **Fast draft** | 补全、草稿 | **fast** `qwen3.5:9b` | ✅ |
| **Embedding / RAG** | 语义检索 | **embed** `qwen3-embedding:8b` | ✅ |
| **Rerank** | RAG 二阶段重排 | **rerank** `awenleven/Qwen3-Reranker-4B:Q4_K_M` | ✅ |
| **Chat / creative** | 闲聊、多语言、创意 | **chat** `gemma4:31b` | ✅ |
| **Reasoning** | 强推理 / 工具思考 | **reason** `gpt-oss:20b` | ✅ |
| **Vision** | 识图 | 已含于 main/deep/fast | ✅（无需独立 VL） |
| **Image gen** | 文生图 / 改图 | mflux Klein + Z-Image | ✅ |
| **Speech ASR** | 语音转写 | **asr** mlx-whisper `whisper-large-v3-turbo` | ✅ |
| **Speech TTS** | 语音合成 | **tts** Kokoro（快）+ **Qwen3-TTS 1.7B**（强） | ✅ |
| **Alignment red-team** | 安全对齐攻防 / 对照 | **redteam** + **redfast** + **heretic** + **crack** | ✅ |
| **Frontier MoE** | Qwen3.8-2.4T / 旗舰 | — | ❌ 装不下 |

## 当前安装清单（v2.9）

| 角色 | 模型 | 大小 | 建议 |
|------|------|------|------|
| **main** | `qwen3.8:27b-q4_K_M` | ~18GB | Agent 主力；最新开源代 |
| **deep** | `qwen3.8:27b-q8_0` | ~30GB | 难题；勿与其它大模型同开 |
| **fast** | `qwen3.5:9b-q4_K_M` | 6.6GB | 草稿（尚无更小的 3.8） |
| **embed** | `qwen3-embedding:8b` | 4.7GB | RAG；可与大模型同开 |
| **rerank** | `awenleven/Qwen3-Reranker-4B:Q4_K_M` | 2.5GB | 检索重排；配合 embed |
| **chat** | `gemma4:31b` | 20GB | 闲聊/创意；勿替 main |
| **reason** | `gpt-oss:20b` | ~14GB | 专用推理；与 main/deep/chat 互斥加载 |
| **redteam** | `huihui_ai/Qwen3.8-abliterated:27b-q4_K_M` | ~18GB | 对齐攻防主力；与 stock main 同基 A/B |
| **redfast** | `jaahas/qwen3.5-uncensored:9b` | ~7.4GB | 廉价探针；可与 embed 同开 |
| **heretic** | `qwen3.8-heretic:27b-q4_K_M` | ~16.5GB | 低拒答 RVN ARA；GGUF 导入 |
| **crack** | `qwen3.8-crack:27b-q4_K_M` | ~17GB | 低拒答 CRACK；GGUF + vision |
| **asr** | `whisper-large-v3-turbo`（mlx） | 1.5GB | `lm asr <audio>` |
| **tts** | `kokoro-82m`（mlx-audio） | ~375MB | 日常快合成；中文 `--voice zf_xiaoxiao` |
| **tts-alt** | `qwen3-tts-1.7b` CustomVoice bf16 | ~4GB | 本机最强：情绪/多说话人/中英；`--model qwen3-tts-1.7b` |

```bash
lm check
lm run main / chat / reason / redteam / redfast / heretic / crack
lm test embed && lm test rerank && lm test reason && lm test asr && lm test tts
lm asr ~/path/to/audio.wav --lang zh
lm tts "Hello" --voice af_heart
lm tts "你好，世界" --voice zf_xiaoxiao --lang z
lm tts "你好" --model qwen3-tts-1.7b --voice Vivian --instruct "平静清晰"
```

原则：一次只常驻一个 ≥18GB 大模型（main / deep / chat / **redteam** / **heretic** / **crack**）；**embed / rerank / asr / tts / fast / reason / redfast** 相对灵活，但仍避免与 deep 同开。

上下文：经 Ollama API 调用时各档**实际都是 32K**（daemon 默认值），manifest 的 `NUM_CTX`
只对手动 GGUF 导入生效。抬高办法见 [environment.md](./environment.md#上下文长度的真实生效路径易踩)。

## 对齐攻防档（redteam / redfast / heretic / crack）

独立分类，**不进 Cursor/Hermes 日常 Agent**。用途：对照 stock 对齐模型做授权红队 / 安全评估（拒答率、越狱鲁棒性、能力保持）。

| 角色 | 模型 | 为何选它 |
|------|------|----------|
| **redteam** | `huihui_ai/Qwen3.8-abliterated:27b-q4_K_M` | 与 `main` 同代同规模（Qwen3.8-27B Q4）；Ollama 原生可拉，含 vision |
| **redfast** | `jaahas/qwen3.5-uncensored:9b` | 与 `fast` 同规模廉价探针；Ollama 可拉（vaultbox 同名 tag 已 404）；huihui 的 3.5 abliteration 拒答仍高 |
| **heretic** | `qwen3.8-heretic:27b-q4_K_M` | RVN 双轮 ARA；自称拒答 0–1/100、KL≈0.0085；GGUF `RVN-Q4_K_M-multilingual.gguf` |
| **crack** | `qwen3.8-crack:27b-q4_K_M` | CRACK abliteration；Q4_K_M ~17GB + mmproj（vision） |

Qwen3.8-27B **有**解除限制变体。huihui 便于和 stock 做同量化 Ollama A/B；**heretic / crack** 拒答更低，走 GGUF 导入（Ollama 无原生 tag）：

```bash
lm deploy redteam                    # ~18GB Ollama 原生
lm deploy redfast                    # ~7.4GB
lm deploy heretic --gguf             # ~16.5GB HF GGUF → ollama create
lm deploy crack --gguf               # ~17GB + mmproj
lm run heretic                       # 对照：lm run main / redteam / crack
lm test heretic && lm test crack
```

仍观察、不默认安装：

| 变体 | 来源 | 备注 |
|------|------|------|
| MiawTeam | `MiawTeam/Qwen3.8-27B-Uncensored-GGUF` | 保留 MTP head |

跨家族对照（不进默认清单，按需 `lm get`）：

| 模型 | 约体积 | 角色 |
|------|--------|------|
| `dolphin3:8b` | ~5GB | 经典无审查微调，跨基座对照 |
| `hermes3:8b` | ~5GB | 中性对齐，边界主要靠 system prompt |
| `vaultbox/qwen3.5-uncensored:9b` | — | 网页仍在，registry 已 404，勿钉 |
| `huihui_ai/llama3.3-abliterated:70b` | ~40GB | 48GB 上限附近，几乎无 KV 余量，不推荐当默认 |

16/24GB lineup **不装** redteam（27B）；需要时在本机 `lm get … --tier redteam`。

## 刻意不做 / 仍缺

| 类别 | 说明 |
|------|------|
| Qwen3.8 MoE / 2.4T-A95B | 尚无适合 48GB 的 Ollama 小 MoE；2.4T 远超预算 |
| gpt-oss:120b | ~65GB，超出本机 |
| Qwen3-TTS Base / VoiceDesign / 更大非 MLX TTS | CustomVoice 1.7B 已是本机最强日常档 |
| 独立 VL | Qwen 原生 vision 已覆盖 |
| Laguna / Ornith | 观察名单，可 `lm get` 试验 |

## 选型要点

- 编码标尺：SWE-bench / 长程 agent；聊天 Arena ≠ Agent 能力（故 Gemma 只进 chat）
- RAG 链路：`embed` 召回 → `rerank` 精排 → `main/deep` 生成
- 推理：日常用 Qwen thinking；专项难题可切 `reason`（gpt-oss:20b）
- v2.9：用 **Qwen3.8-27B** 替换原 Qwen3.6 三档中的 main/deep（3.8 暂无 A3B MoE）

## LM Studio 用 GGUF（与 Ollama 并行）

Ollama 装的是运行时副本；给 LM Studio 用时把 **同一套 Unsloth GGUF** 落到 `~/models/gguf/`（`~/.lmstudio/models/llm-gguf` → symlink）：

| 角色 | GGUF 文件（HF Unsloth） | 约体积 |
|------|-------------------------|--------|
| main | `Qwen3.8-27B-Q4_K_M.gguf` + `mmproj-F16.gguf` | ~18GB |
| deep | `Qwen3.8-27B-Q8_0.gguf` + mmproj | ~30GB |
| fast | `Qwen3.5-9B-Q4_K_M.gguf` + mmproj | ~6.6GB |

```bash
lm pull-gguf main deep fast --link   # 断点续传；刷新 LM Studio symlink
# LM Studio → My Models → llm-gguf；需要识图时一并加载 mmproj
```

chat / reason / embed / rerank 目前以 Ollama 为主（无稳定 HF_GGUF_URL），不必强行再下一份 GGUF。
