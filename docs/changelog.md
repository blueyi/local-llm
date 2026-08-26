# Changelog

## 2026-08-27（运行时：Ollama 0.32.13 → 0.33.0）

- `lm upgrade-ollama --yes`：GitHub latest 装到 `/opt/homebrew/opt/ollama-upstream`，daemon 已重启；`docs/environment.md` 运行时版本同步。

## 2026-08-26（配置合理性审计：推荐打分、对账口径、上下文口径）

审计发现的三处不合理并修复（模型清单本身未改动）：

- **`lm update` 会把 main 退回上一代**：`recommend_tiers` 里家族优先级权重（`pri * 3`）小于
  `MAIN_PREFER_MOE` 的 ±16 分摆动，导致 `qwen3.6:35b-a3b-q4_K_M` 以 9.3 分优势压过
  `qwen3.8:27b-q4_K_M`，越过 `STABILITY_MARGIN=4` 被判定为 CHANGE。
  新增 `FAMILY_PRIORITY_WEIGHT`（默认 12，写入 `config/update-policy.conf`）；
  `lm update --dry-run` 复验后三档均为 same。
- **`lm check` 看不到退役模型**：`reconcile()` 只报 active 档缺失，`lm status` 却会标
  prune candidate。补 `report_stale()`，`lm check` 现在同时列 retired / extra 及占盘提示。
- **上下文口径与实际不符**：manifest 的 `NUM_CTX` 仅作用于手动 GGUF 导入；`ollama pull`
  的官方 tag 不带 `num_ctx`，`OLLAMA_CONTEXT_LENGTH` 本机未设置，故各档经 API 实际都是
  **32K**（`ollama ps` 已验证），而非文档宣称的 main 64K。
  `docs/environment.md` 新增「上下文长度的真实生效路径」，`tiers.md` / `agent-integration.md` 同步纠正。
- 文档：`lm deploy --prune` 之前只写在 `deploy.sh` 注释里，补进 `lm help` 与 README 维护段。

## 2026-08-16（脚本结构重构：统一 HF / GGUF 辅助入口）

- 新增 `scripts/pull-hf-model.sh`，统一 image、speech、TTS 的 manifest 解析与 Hugging Face 下载；原 `pull-image-model.sh`、`pull-speech-model.sh`、`pull-tts-model.sh` 保留为兼容 wrapper。
- `pull-gguf.sh` 内置 LM Studio symlink 操作，支持 `--link-only`；原 `link-lmstudio-models.sh` 保留为兼容 wrapper。
- 核心命令脚本继续独立，避免把 deploy/status/smoke-test 等复杂流程合并成不可维护的大脚本。

## 2026-08-16（脚本重构：公共库、HF 下载与 SSOT 漂移修复）

- 新增 `scripts/lib/common.sh`：统一日志、manifest 字段解析和 Ollama tag 查询，供 deploy/get/update/status/asr/tts/rm 等入口复用。
- 新增 `scripts/lib/hf_download.sh`：统一 image/speech/tts 的 HF 文件清单、302 解析、Range 续传、大小校验和失败退出码；下载失败不再被静默吞掉。
- `import-all-gguf` 改为按 `config/models.manifest` 动态导入，移除旧模型名/上下文硬编码。
- 修正 README、defaults、install、operations 中仍指向 Qwen3.6 的当前默认示例；历史 changelog 与 retired manifest 条目保留作审计记录。
- 验证：`bash -n bin/lm scripts/*.sh scripts/lib/*.sh`、`python3 -m py_compile scripts/lib/model_catalog.py`、`lm check` 全部通过。

## 2026-08-15（`lm pull-gguf`：HTTP/1.1 抗 CDN 断流）

- 大文件下载改用 `--http1.1` + 外层重解析 URL（避免 curl 死磕过期 CDN / DNS 失败）
- 退避计算去掉 bash4 `?:` 三元运算，兼容 macOS `/bin/bash` 3.2
- 续传仍比对 Content-Length；不完整文件直接 `lm pull-gguf main --link` 即可

## 2026-08-15（`lm status`：场景角色表）

- `lm status` 新增 **Scenario roles** 段：按 `models.manifest` 列出 main/deep/fast/embed/chat/reason/rerank 的场景说明、配置模型与本地是否已装
- `ollama list` 注解 ROLE（active / retired / extra）；GGUF 不完整文件标 ⚠ INCOMPLETE
- `docs/models-registry.md` 改为「场景角色 → 当前配置」表；七档 LLM 均已 installed

## 2026-08-15（`lm deploy` 前自动检查 Ollama 版本）

- 新增 `scripts/upgrade-ollama.sh` / **`lm upgrade-ollama`**：对照 GitHub latest；darwin 自动装到 `/opt/homebrew/opt/ollama-upstream` 并重启 daemon
- **`lm deploy`** 部署前调用：落后则交互确认（`Y` 升级 / `n` 跳过继续）；`--yes` 自动升级；`--skip-ollama-upgrade` 跳过检查
- 避免再出现 `qwen3.8` 之类因引擎过旧返回 412 却未先升运行时的问题

## 2026-08-15（运行时：Ollama 0.32.12 for Qwen3.8）

- 库拉取 `qwen3.8` 需 **Ollama ≥0.32.12**（官方 release 当日加入支持）；Homebrew stable 当时仍为 0.32.11 → 412
- 本机改为官方 `ollama-darwin.tgz` → `/opt/homebrew/opt/ollama-upstream`，LaunchAgent 指向该二进制；`docs/environment.md` 同步

## 2026-08-15（`lm rm` + `lm deploy --force`）

- 新增 **`lm rm <name|tier> [--yes]`**：封装 `ollama rm`，执行前确认提示；档位名可解析；删后自动 sync registry
- **`lm deploy --force`**：已装 tag 也重新 `ollama pull`（默认仍跳过已装）
- 文档：AGENTS / README / operations 同步；禁止再直接写 `ollama rm`

## 2026-08-15（v2.9：全面换代 — Qwen3.8 + embed8b + gemma4:31b）

按最新远程目录与 48GB 预算重排：

| 档位 | 原 | 新 |
|------|----|----|
| main | `qwen3.6:35b-a3b-q4_K_M` | **`qwen3.8:27b-q4_K_M`**（~18GB，最新开源代） |
| deep | `qwen3.6:27b-q8_0` | **`qwen3.8:27b-q8_0`**（~30GB） |
| fast | `qwen3.5:9b` | 保持（尚无更小的 3.8） |
| embed | `qwen3-embedding:4b` | **`qwen3-embedding:8b`**（4.7GB） |
| chat | `gemma4:26b` | **`gemma4:31b`**（20GB） |
| reason / rerank | 不变 | `gpt-oss:20b` / Qwen3-Reranker-4B |

- `config/update-policy.conf`：`FAMILIES` 优先 `qwen3.8`
- GGUF：`unsloth/Qwen3.8-27B-GGUF`（Q4_K_M / Q8_0 + mmproj）
- 不做：`qwen3.8:27b-bf16`（56GB）、`gpt-oss:120b`（65GB）、3.8-2.4T
- **运行时**：Ollama 库内 `qwen3.8` 要求比 brew stable 更新的引擎；本机升至可用版本后用 `ollama pull`，否则走 Unsloth GGUF 导入（`lm deploy` 自动回退）

## 2026-08-02（v2.8.1：TTS 质量档 Qwen3-TTS 1.7B CustomVoice）

- 新增 **alt** `qwen3-tts-1.7b`：`mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-bf16`（~4GB，本机最强可用）
- 保留 **primary** Kokoro 作日常快路径；`lm tts --model qwen3-tts-1.7b`，支持 `--instruct` 情绪/风格
- 中文默认说话人 `Vivian`，英文 `Serena`（CustomVoice 内置：serena/vivian/uncle_fu/ryan/aiden/…）

## 2026-08-02（v2.8：Speech TTS — Kokoro-82M + mlx-audio）

- **选型**：`mlx-community/Kokoro-82M-bf16`（~312MB 权重 + 多音色；Apache；中英；Apple Silicon MLX）
- 新增 `config/tts-models.manifest`、`lm pull-tts`、`lm tts`、`lm test tts`；权重目录 `~/models/tts/`
- 引擎：`uv tool install mlx-audio --with 'misaki[en]' --with 'misaki[zh]'`；英语另需 `brew install espeak-ng` + `en_core_web_sm` 装入 tool 环境
- 默认英音 `af_heart`；中文启发式切 `zf_xiaoxiao` / `--lang z`
- 文档：tiers / registry / operations / AGENTS / README 同步；TTS 从「暂缺」标为已装

## 2026-08-02（`lm pull-gguf`：为 LM Studio 落盘 Unsloth GGUF）

- 新增 `lm pull-gguf [tier...] [--link]`：按 `models.manifest` 的 `HF_GGUF_URL` 断点续传下载到 `~/models/gguf/`，并刷新 `~/.lmstudio/models/llm-gguf` symlink
- 推荐本机三套：35B-A3B Q4_K_M / 27B Q8_0 / 9B Q4_K_M（+ mmproj）
- 与 Ollama 权重分离；文档 tiers/operations 补充 LM Studio 用法

## 2026-08-02（v2.7：补齐 reason / rerank / speech ASR）

对照常用分类缺口补装：

- **reason**：`gpt-oss:20b`（13GB，专用推理）
- **rerank**：`awenleven/Qwen3-Reranker-4B:Q4_K_M`（2.5GB，配对 embed）
- **speech ASR**：mlx-whisper + `whisper-large-v3-turbo`（`config/speech-models.manifest`，`lm asr` / `lm pull-speech`）
- TTS 仍缺；独立 VL / 旗舰 MoE 仍不做
- `lm test asr|reason|rerank`；`status` 显示 speech 权重

## 2026-08-02（v2.6：场景分类补齐 — embed + chat）

对照业界本地开源分类（coding / deep / fast / embedding / chat-creative / vision / image-gen）：

- **维持** main/deep/fast：`qwen3.6:35b-a3b-q4_K_M` / `qwen3.6:27b-q8_0` / `qwen3.5:9b`（48GB 上编码仍为消费级 SOTA）
- **新增 embed**：`qwen3-embedding:4b`（RAG 缺口）
- **新增 chat**：`gemma4:26b`（Arena/多语言/创意；明确不进 Agent main）
- **刻意不做**：独立 VL、R1 distill、Coder-Next 80B、旗舰 MoE（装不下或已被覆盖）
- `deploy` / `lm test` / `lm get --tier` 支持 `embed|chat`；`docs/tiers.md` 重写为分类矩阵

## 2026-07-27（v2.5：`lm update` / `lm get` 远程发现 + 硬件感知更新）

- **`lm update`**：从 ollama.com 拉取候选 tag，结合本机硬件（默认 `sysctl` 探测；可 `--ram` / `--chip` 覆盖）按 `config/update-policy.conf` 为 main/deep/fast 打分推荐；**更新前确认**；确认后写 `config/models.manifest` 并 `lm deploy`（`--dry-run` / `--yes` / `--no-deploy`）。
- **`lm get <query>`**：远程模糊搜索 → 家族/tag 不唯一时交互选择 → `ollama pull`；可选 `--tier` 写入清单。
- 新增：`scripts/lib/model_catalog.py`、`scripts/update-models.sh`、`scripts/get-model.sh`、`config/update-policy.conf`。
- 评分含稳定性阈值（避免 MTP/同体积别名无意义抖动）；排除 mlx/bf16 自动入选。
- 文档：AGENTS / README / operations 同步。

## 2026-07-22（v2.4.1：代码/脚本/配置全英文化）


- `bin/lm` + `scripts/*.sh` + `config/*.manifest` + `config/defaults.env.example` + `integrations/*/README.md`：注释、帮助文本、日志输出全部改为英文（规则：代码内容一律英文；docs/ 仍为中文文档）。
- 顺带修复：`import-all-gguf.sh` 中两处指向已删除 `docs/manual-download.md` 的引用 → `docs/install.md`；清除 `config/.DS_Store`。
- 验证：`bash -n` 全过；`lm check` 三档 ✓；`lm test fast` 77.8 tok/s；`lm image` 出图 ✓；CJK 扫描 bin/scripts/config/integrations 零残留。

## 2026-07-22（v2.4：统一 CLI 入口 lm + 仓库重组）

**动机**：用法分散在 9 个脚本 + 10 份文档中，无统一入口；文生图模型无 SSOT。

- **新增 `bin/lm` 统一 CLI**（symlink → `~/.local/bin/lm`）：status / run / test / image / check / deploy / pull-image / import / sync 九个子命令，分发到 scripts/。scripts/ 降级为实现细节，不再直接调用。
- **新增 `config/image-models.manifest`**：文生图模型 SSOT（role|id|hf_repo|gen_cli|edit_cli|base_arg|steps），与 LLM manifest 平行；`scripts/gen-image.sh` 读它统一包装出图/改图。
- **`lm image` 实测**：Klein 512² 4 步 ~1s 生成、z-image-turbo ✓、`--edit` 改图 ✓、缺权重时提示 `lm pull-image` ✓。
- **docs 10→8 份**：`hardware.md`+`stack.md` → `environment.md`；`manual-download.md` 并入 `install.md`（安装+回退一处看完）。
- **删除**：`scripts/pull-tier.sh`（deploy.sh 已带 a/b/c 兼容映射）、`.tmp/` 垃圾。
- **`lm status` 增强**：显示 `~/models` 权重目录 + symlink 健康检查 + 文生图权重对账。
- **`lm test`（smoke-test.sh）重写**：走 API 报 tok/s（原来 `ollama run` 无速度数据）；支持档位名（`lm test fast`）。
- README 重写为完整工程门面：目录结构、lm 全命令、三档表、文生图表、Agent 对接矩阵、设计原则。

## 2026-07-22（v2.3：权重统一目录 ~/models/）

所有本地模型权重收拢到统一根目录 `~/models/`，三个子目录：

| 子目录 | 内容 | 大小 | 接入方式 |
|--------|------|------|----------|
| `~/models/ollama/` | Ollama 三档权重（原 `~/.ollama/models`） | 56GB | `~/.ollama/models` → symlink（停服务后 mv+ln，重启验证 3 模型完好） |
| `~/models/image-gen/` | FLUX.2 Klein 4B + Z-Image-Turbo（原 `~/Downloads/image-gen-models/`） | 9.8GB | mflux `--model` 直接路径；Hermes 插件 `DEFAULT_MODELS_DIR` 已改 |
| `~/models/gguf/` | 手动 GGUF 落盘（原 `~/Downloads/llm-gguf/`，当前为空） | 0 | `deploy.sh` 的 `LLM_GGUF_DIR` 默认值已改；`~/.lmstudio/models/llm-gguf` symlink 已重指 |

同步修改：`scripts/{deploy,pull-image-model,import-gguf,import-all-gguf,link-lmstudio-models}.sh` 默认路径、`AGENTS.md` 路径约定表、`docs/{image-gen,manual-download,models-registry,operations}.md`、`README.md`、Hermes 插件 `~/.hermes/plugins/image_gen/mflux/__init__.py`（+ integrations 备份同步）。历史 changelog 条目保留旧路径不改写。

## 2026-07-22（Hermes image_generate 接入本地 mflux）

- 新增 user plugin `~/.hermes/plugins/image_gen/mflux/`：实现 `ImageGenProvider` ABC，subprocess 包装 `mflux-generate-flux2`（+ `flux2-edit` 图生图）与 `mflux-generate-z-image-turbo`
- config.yaml：`plugins.enabled += image_gen/mflux`，`image_gen.provider: mflux`，`image_gen.model: flux2-klein-4b`（原 FAL 云端配置被本地取代，随时可切回）
- 验证链路 3 层全过：registry 注册（6 provider 中 active=mflux）→ `_handle_image_generate` 端到端 → Hermes 会话内 `image_generate` 实际出图 + 识图确认
- 输出落 `~/.hermes/cache/images/mflux_*.png`；aspect_ratio 映射 landscape=1024×576 / square=768² / portrait=576×1024
- 改前备份 `~/.hermes/config.yaml.bak-20260722-*`

## 2026-07-22（MLX 版对比实测 → 不换，main 档维持 GGUF）

`qwen3.6:35b-mlx`（21GB, nvfp4）vs `qwen3.6:35b-a3b-q4_K_M`（GGUF），冷加载 + 3 场景 + 8K 长 prompt：

| 指标 | GGUF q4_K_M | MLX nvfp4 | 结论 |
|------|-------------|-----------|------|
| 短答生成 | 104.7 t/s | 124.8 t/s | MLX +19% |
| 代码生成 | 102.7 t/s | 114.4 t/s | MLX +11% |
| 长文生成 | 101.6 t/s | 103.0 t/s | 持平 |
| **8K prompt 处理** | **2086 t/s** | 1168 t/s | **GGUF 快 1.8×** |
| tools 调用 | ✓ | ✓ | 持平 |
| **识图** | ✓ | **✗ 失败**（3 次均称"无法查看图片"，nvfp4 版视觉输入断路） | **GGUF 独有** |

- 决策：**main 档维持 `qwen3.6:35b-a3b-q4_K_M`**。理由：(1) Agent 场景瓶颈是长 prompt 处理，GGUF 快 1.8×，远盖过 MLX 生成端 +11~19%；(2) MLX 版识图实际不可用（Capabilities 标 vision 但推理断路），会砍掉三档的原生多模态卖点
- MLX 版已 `ollama rm`；tiers.md 观察名单已记录

## 2026-07-22（外部推荐清单 cross-check：维持 v2.1 不变）

Leon 转来一份"48GB Apple Silicon 最强本地模型"推荐清单，逐项对照 ollama.com 实测：

- **Qwen 3.6 35B-A3B / 3.5 27B** → 已是 main 档，清单还漏了原生 vision + 256K ctx 优势
- **DeepSeek-R1-Distill-32B** → ollama 全系 tag "1 year ago"（2025 初模型），纯文本 128K，已被 Qwen3.6 超越，不换
- **Gemma 4 31B/26B** → 已评估拒绝（SWE-bench V 17.4 vs 73.4，见 tiers.md 专节）
- **Qwen3-Coder-30B** → 上一代，v2 已退役
- **Kimi K2.5 / GLM-5.2 / DeepSeek-V4 / MiniMax-M3** → ollama 均 cloud-only 无本地权重；GLM-4.7-Flash 本地 19GB 可跑但 SWE 59.2 弱于 Qwen3.6 且纯文本
- **独立 Qwen3-VL** → 冗余（三档原生多模态），v2 已退役
- **Nemotron-Super 49B** → 2025 老模型，30–34GB 挤占全部预算，不进
- **结论：三档 v2.1 全部维持**；此类外部清单常滞后 2–6 个月，以 ollama.com/tags 实测 + SWE-bench V 为准
- **增量采纳**：清单中"本地文生图"为本方案空白 → 新增 image-gen 能力（见下条）

## 2026-07-22（v2.2 — 本地文生图能力落地）

- **安装**：`uv tool install mflux 0.18.0`（MLX 原生，32 个 CLI 入口）
- **主力模型**：`Runpod/FLUX.2-klein-4B-mflux-4bit`（4.3GB）→ `~/Downloads/image-gen-models/`；备选写实向 `filipstrand/Z-Image-Turbo-mflux-4bit`（5.9GB）
- **冒烟实测（M5 Max）**：768×768 ×4 步 = **3.2s 生成**（含加载共 7.3s），**峰值 MLX 内存 7.96GB** → 可与 main 档 LLM（23GB）同跑；识图验证出图内容正确
- **选型**：FLUX.2 Klein（2026-01, 4B）取代外部清单推荐的 FLUX.1 Schnell（2024-08, 12B, mflux 官方标 legacy）—— 更小、更快、原生编辑；CLI 方案（mflux）优于 Draw Things（App Store 装需 sudo，不可脚本化）
- **坑**：huggingface_hub 对 hf-mirror 报 `FileMetadataError`（重定向域名校验），hub 客户端全挂 → 新增 `scripts/pull-image-model.sh` 用 curl 逐文件直拉，`--model <本地路径>` 加载
- 新增 `docs/image-gen.md`；README / AGENTS.md 同步

## 2026-07-22（Hermes fallback 接入本地模型）

- 三档全部就绪（deploy.sh 对账 ✓✓✓），main/deep/fast 无缺
- **Hermes 集成**：`~/.hermes/config.yaml` 注册 `local-ollama` provider（`http://127.0.0.1:11434/v1`），fallback 链末尾追加 `qwen3.6:35b-a3b-q4_K_M`（main）→ `qwen3.5:9b`（fast）兜底；云端 provider 全挂时自动切本地
- 验证：`hermes chat -q ... --provider local-ollama` 端到端回复正常；`hermes config check` 合法
- 坑：Qwen3.6 thinking 模型 OpenAI 兼容接口下 reasoning 占 token，`max_tokens` 需 ≥2048，否则 content 为空（finish=length）
- 改前备份：`~/.hermes/config.yaml.bak-20260721-*`

## 2026-07-22（清理 + 档位改名 + Gemma 4 评估）

- **磁盘清理**：`deploy.sh --prune` 删除 4 个退役模型 → coder q8 (32GB) + coder q4 (18GB) + 35b-a3b-q8_0 (38GB)，释放 **88GB**（可用盘 1.5Ti→1.6Ti）
- **档位改名**（A/B/C 不好记 → 按用途取名）：
  - `b` → **main**（日常主力）
  - `a` → **deep**（深度质量，难题用）
  - `c` → **fast**（极限速度，赶时间用）
  - deploy.sh 兼容旧 a/b/c 参数自动映射；manifest/docs/env 全部同步
- **Gemma 4 评估（结论：不进三档）**：编码/Agent 差距悬殊 —— SWE-bench Verified 17.4 vs Qwen3.6 的 73.4（-56 分）、MCP 工具调用约一半、社区报告 tool-call 需 JSON 修补 + 多轮 bug；Arena ELO 高（31B 排 #3）但那是聊天偏好信号，非工程能力。它赢的维度（多语言、创意、视频、edge）非本机主用途。`gemma4:26b` 列入观察名单作聊天/创意备选
- **全球最新复核（ollama.com newest, 2026-07-22）**：glm-5.2 / kimi-k2.7-code / nemotron-3-ultra / minimax-m3 均 cloud-only 不可本地；本地可跑新模型中无超越 Qwen3.6-35B-A3B 者。方案 v2.1 维持 Qwen3.6/3.5 三档

## 2026-07-22（三档部署完成 + 冒烟验证）

- `./scripts/deploy.sh` 一键跑通：A `qwen3.6:27b-q8_0`（29GB，~99MB/s 拉取）+ C `qwen3.5:9b`（6.6GB）落地；B 此前已装。三档对账全 ✓
- 冒烟（M5 Max 48GB，100% GPU）：
  - B `qwen3.6:35b-a3b-q4_K_M` @32K ctx：**104 tok/s**（load 5.0s）
  - A `qwen3.6:27b-q8_0` @16K ctx：**18 tok/s**（稠密 27B Q8，load 7.9s）
  - C `qwen3.5:9b`：**77 tok/s**；原生识图验证 ✓（正确辨认测试图标）
- 发现遗留 `qwen3.6:35b-a3b-q8_0`（38GB，旧后台拉取残留）→ 加入 manifest retired 段
- 待清理（`./scripts/deploy.sh --prune`，可释约 88GB）：coder q8 32GB + coder q4 18GB + 35b-a3b-q8_0 38GB

## 2026-07-21（一键部署 + 断点续传）

- 新增 **`config/models.manifest`**：模型清单 SSOT（档位|tag|ctx|GGUF 回退直链|mmproj），升级模型只改此文件
- 新增 **`scripts/deploy.sh`**：一键部署
  - 幂等：已装跳过；`--check` 只对账；`--prune` 交互式清理 retired 模型；`a|b|c` 只装单档
  - 安装策略：首选 `ollama pull`（原生断点续传）→ 失败回退 GGUF 手动下载+导入
  - GGUF 断点续传实测验证：先解析 302 → 最终 CDN URL（xethub，支持 HTTP 206），再 `curl -C -` 续传；直接对镜像首跳 `-L -C -` 会报 "doesn't support byte ranges"（已修）；已完整文件按 Content-Length 比对跳过；CDN 签名过期由 5 次重试重新解析覆盖
  - 镜像：默认 `HF_ENDPOINT=https://hf-mirror.com`（本机 huggingface.co 直连不通），可 env 覆盖
- `pull-tier.sh` 降级为兼容 wrapper（转发 deploy.sh），消除脚本内硬编码模型名
- AGENTS.md / README 写入 SSOT 规则与升级流程

## 2026-07-21（方案 v2 — 模型线升级）

**背景**：原方案基于 Qwen3 一代（qwen3-coder / qwen3-vl / qwen3:8b，2025 年中模型）。核对 Ollama 库（2026-07）后确认已落后两代，升级为 Qwen3.6 / Qwen3.5 原生多模态线。

- **B 档主力**：`qwen3-coder:30b-a3b-q4_K_M` → **`qwen3.6:35b-a3b-q4_K_M`**（24GB，256K ctx，原生 vision + tools + thinking；SWE-bench Verified 73.4% / Terminal-Bench 2.0 51.5%，超过 Laguna XS 2.1、North Mini Code、GLM-4.7-Flash 等同级编码专用模型）
- **A 档**：`*-q8_0` 系列 → **`qwen3.6:27b-q8_0`**（30GB 稠密 27B）。原定 `qwen3.6:35b-a3b-q8_0` 实际 39GB，超出 34–38GB 内存预算，弃用；备选 unsloth UD-Q6_K（29GB）手动导入
- **C 档**：`qwen3:8b` + `qwen3-vl:8b` 两个 → **`qwen3.5:9b`** 一个（6.6GB，原生 vision）
- **VL 线整体退役**：Qwen3.6/3.5 原生多模态，独立 `qwen3-vl:*` 不再需要；LM Studio 退为纯备用 GUI
- **退役待删**：`qwen3-coder:30b-a3b-q8_0`（32GB，已装）验证新主力后 `ollama rm`；取消 `qwen3-coder:30b-a3b-q4_K_M` 等所有 pending 拉取
- **观察名单**：`ornith:35b`（MIT，agentic coding SOTA 宣称）；`laguna-xs-2.1`（macOS 已知问题，待修复）；`glm-4.7-flash`（SWE-bench 59.2，弱于 Qwen3.6）
- 同步更新：`tiers.md` / `models-registry.md` / `agent-integration.md` / `manual-download.md`（含 hf-mirror.com 提示）/ `pull-tier.sh` / `defaults.env.example` / `README.md`
- 网络注：本机当前 `huggingface.co` 直连不通，`hf-mirror.com` 与 `ollama.com` 可达

## 2026-07-21

- Ollama 已装：`qwen3-coder:30b-a3b-q8_0`（32GB）、`qwen3.6:35b-a3b-q4_K_M`（23GB）
- **LM Studio 已升级**：`0.4.2+2` → **`0.4.19+2`**
- 新增脚本：`import-gguf.sh` / `import-all-gguf.sh` / `link-lmstudio-models.sh` / `smoke-test.sh`
- `~/.lmstudio/models/llm-gguf` → `~/Downloads/llm-gguf` 符号链接已建
- 冒烟：`qwen3.6:35b-a3b-q4_K_M` 推理正常（约 85 tok/s eval）
- 后台仍在拉：`qwen3-coder:30b-a3b-q4_K_M`、`qwen3.6:35b-a3b-q8_0` 等（`.tmp/pull-remaining.log`）
- Cursor 现可用：Base `http://127.0.0.1:11434/v1`，模型 `qwen3-coder:30b-a3b-q8_0` 或 `qwen3.6:35b-a3b-q4_K_M`

## 2026-07-20

- 初始化知识库 `~/workspace/local-llm`（docs / scripts / config）
- 硬件基线：M5 Max / 48GB / 40 GPU（见 `docs/hardware.md`）
- 安装 **Ollama 0.32.1**（brew，依赖 MLX 0.32.0），`brew services start ollama`
- `/Applications/LM Studio.app` 已存在；brew cask 安装可能仍在进行（可选）
- 定案精确 tag（Ollama 库核对）：
  - B: `qwen3-coder:30b-a3b-q4_K_M` / `qwen3.6:35b-a3b-q4_K_M` / `qwen3-vl:30b-a3b-instruct-q4_K_M`
  - A: 同系 `q8_0`
  - C: `qwen3:8b` / `qwen3-vl:8b-instruct-q4_K_M`
- 启动子 agent 并行 `ollama pull` 一度互相抢带宽卡住；已改为**串行**拉取（C→B→A），日志：`.tmp/pull-sequential.log`
- `brew cask lm-studio` 下载失败（连接重置）；本机已有 `/Applications/LM Studio.app`，不影响主路径
- 用户要求：本仓库任务默认直接执行写入/安装/拉模型，勿反复确认（已写入 `AGENTS.md`）
- 因 Ollama 官方源过慢：改为用户手动下载 GGUF；指引见 `docs/manual-download.md`；已停止本机串行 `ollama pull`
