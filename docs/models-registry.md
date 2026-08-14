# 模型登记（活文档）

权重统一在 `~/models/`（ollama/ gguf/ image-gen/ speech/ tts/）；此处只登记元数据。

更新：`lm sync` 或手动编辑。

## 目标清单（v2.9，2026-08-15）

### main / deep / fast

| 短名 | 用途 | 状态 |
|------|------|------|
| qwen3.8:27b-q4_K_M | Agent / 编码 / 识图主力 | **installing** |
| qwen3.8:27b-q8_0 | 深度质量 | **installing** |
| qwen3.5:9b | 极限速度 | **installed** |

### embed / rerank（RAG）

| 短名 | 用途 | 状态 |
|------|------|------|
| qwen3-embedding:8b | 向量检索 | **installing** |
| awenleven/Qwen3-Reranker-4B:Q4_K_M | 二阶段重排 | **installed** |

### chat / reason

| 短名 | 用途 | 状态 |
|------|------|------|
| gemma4:31b | 闲聊 / 创意 / 多语言 | **installing** |
| gpt-oss:20b | 专用推理 | **installed** |

### speech ASR（非 Ollama）

| 短名 | 路径 | 状态 |
|------|------|------|
| whisper-large-v3-turbo | `~/models/speech/whisper-large-v3-turbo` | **installed** |

### speech TTS（非 Ollama）

| 短名 | 路径 | 状态 |
|------|------|------|
| kokoro-82m | `~/models/tts/Kokoro-82M-bf16` | **installed**（primary / 快） |
| qwen3-tts-1.7b | `~/models/tts/Qwen3-TTS-12Hz-1.7B-CustomVoice-bf16` | **installed**（alt / 质量） |

## Ollama 已装（自动段）

<!-- BEGIN OLLAMA LIST -->
```
NAME                                  ID              SIZE      MODIFIED      
gpt-oss:20b                           17052f91a42e    13 GB     4 minutes ago    
awenleven/Qwen3-Reranker-4B:Q4_K_M    086092f9af6f    2.5 GB    6 minutes ago    
gemma4:26b                            5571076f3d70    17 GB     2 hours ago      
qwen3-embedding:4b                    df5bd2e3c74c    2.5 GB    2 hours ago      
qwen3.5:9b                            6488c96fa5fa    6.6 GB    11 days ago      
qwen3.6:27b-q8_0                      cd0210c667bf    29 GB     11 days ago      
qwen3.6:35b-a3b-q4_K_M                07d35212591f    23 GB     12 days ago      
```
<!-- END OLLAMA LIST -->
