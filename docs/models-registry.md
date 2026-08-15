# 模型登记（活文档）

权重统一在 `~/models/`（ollama/ gguf/ image-gen/ speech/ tts/）；此处只登记元数据。

更新：`lm sync` 或手动编辑。

当前清单版本：v2.9（2026-08-15）；模型角色与安装 SSOT 为 `config/models.manifest`，本次脚本重构未改变已安装模型。

## 场景角色 → 当前配置（v2.9，SSOT: `config/models.manifest`）

| 角色 | 场景 | 模型 | 状态 |
|------|------|------|------|
| **main** | Agent / 编码 / 识图 | `qwen3.8:27b-q4_K_M` | **installed** |
| **deep** | 难 bug / 质量 | `qwen3.8:27b-q8_0` | **installed** |
| **fast** | 草稿 / 补全 | `qwen3.5:9b` | **installed** |
| **embed** | RAG 检索 | `qwen3-embedding:8b` | **installed** |
| **rerank** | RAG 重排 | `awenleven/Qwen3-Reranker-4B:Q4_K_M` | **installed** |
| **chat** | 闲聊 / 创意 / 多语言 | `gemma4:31b` | **installed** |
| **reason** | 专用推理 | `gpt-oss:20b` | **installed** |
| **asr** | 语音转写 | `whisper-large-v3-turbo`（mlx） | **installed** |
| **tts** | 语音合成（快） | `kokoro-82m` | **installed** |
| **tts-alt** | 语音合成（强） | `qwen3-tts-1.7b` | **installed** |

查看实时对照：`lm status`（Scenario roles 段）。

## Ollama 已装（自动段）

<!-- BEGIN OLLAMA LIST -->
```
NAME                                  ID              SIZE      MODIFIED     
gemma4:31b                            6316f0629137    19 GB     12 hours ago    
qwen3-embedding:8b                    64b933495768    4.7 GB    13 hours ago    
qwen3.8:27b-q8_0                      8f5fb6b71ea0    29 GB     13 hours ago    
qwen3.8:27b-q4_K_M                    25b843619e94    17 GB     22 hours ago    
gpt-oss:20b                           17052f91a42e    13 GB     13 days ago     
awenleven/Qwen3-Reranker-4B:Q4_K_M    086092f9af6f    2.5 GB    13 days ago     
gemma4:26b                            5571076f3d70    17 GB     13 days ago     
qwen3-embedding:4b                    df5bd2e3c74c    2.5 GB    13 days ago     
qwen3.5:9b                            6488c96fa5fa    6.6 GB    3 weeks ago     
qwen3.6:27b-q8_0                      cd0210c667bf    29 GB     3 weeks ago     
qwen3.6:35b-a3b-q4_K_M                07d35212591f    23 GB     3 weeks ago     
```
<!-- END OLLAMA LIST -->
