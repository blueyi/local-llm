# 模型登记（活文档）

权重在 `~/.ollama/`（或 LM Studio 目录）；此处只登记元数据。

更新：`./scripts/sync-registry.sh` 或手动编辑。

## 目标清单（按档，2026-07-22 方案 v2.1：main/deep/fast）

### main — 日常主力

| 短名 | 来源 | 量化 | 用途 | 状态 |
|------|------|------|------|------|
| qwen3.6:35b-a3b-q4_K_M | ollama | Q4_K_M (24GB) | 编程 / Agent / 通用 / 识图 全能主力 | **installed** |
| qwen3.6:35b-a3b-mtp-q4_K_M | ollama | Q4_K_M+MTP (23GB) | 同上，解码更快（可选平替） | optional |
| qwen3.6:35b-mlx | ollama | MLX 4bit (22GB) | 同上，MLX 引擎（可选平替） | optional |

### deep — 深度质量

| 短名 | 来源 | 量化 | 用途 | 状态 |
|------|------|------|------|------|
| qwen3.6:27b-q8_0 | ollama | Q8_0 (29GB, 稠密 27B) | 难 bug / 精读 / 复杂推理 | **installed** |
| Qwen3.6-35B-A3B-UD-Q6_K | unsloth GGUF 手动导入 | UD-Q6_K (29GB) | A 档备选（MoE 快 + 高精度） | optional |

### fast — 极限速度

| 短名 | 来源 | 量化 | 用途 | 状态 |
|------|------|------|------|------|
| qwen3.5:9b | ollama | Q4_K_M (6.6GB) | 草稿 / 补全 / 快速扫图（原生 vision） | **installed** |

### 退役（2026-07-21，见 changelog）

| 短名 | 处置 |
|------|------|
| qwen3-coder:30b-a3b-q8_0 (32GB) | 已装 → 被 Qwen3.6 取代，验证新主力后 `ollama rm` |
| qwen3-coder:30b-a3b-q4_K_M | pending → 取消拉取 |
| qwen3-vl:30b-a3b-instruct-* / qwen3-vl:8b-* | 取消（Qwen3.6/3.5 原生多模态） |
| qwen3:8b | 取消（由 qwen3.5:9b 替代） |
| qwen3.6:35b-a3b-q8_0 | 取消（39GB 超内存预算） |

## 建议上下文（48GB）

| 档位 | 文本 | 多模态 |
|------|------|--------|
| main (23GB) | 32K–64K | 32K–64K + 少图 |
| deep (29GB) | 16K–32K | 8K–16K |
| fast (6.6GB) | 8K–32K | 8K–32K |

同时只加载一个大模型（≥18GB）。

## Ollama 已装（自动段）

<!-- BEGIN OLLAMA LIST -->
```
NAME                      ID              SIZE      MODIFIED          
qwen3.5:9b                6488c96fa5fa    6.6 GB    About an hour ago    
qwen3.6:27b-q8_0          cd0210c667bf    29 GB     About an hour ago    
qwen3.6:35b-a3b-q4_K_M    07d35212591f    23 GB     16 hours ago         
```
<!-- END OLLAMA LIST -->

## 导入脚本

```bash
./scripts/import-gguf.sh <name> ~/Downloads/llm-gguf/xxx.gguf
./scripts/import-all-gguf.sh
./scripts/link-lmstudio-models.sh
```

手动直链见 [manual-download.md](./manual-download.md)。
