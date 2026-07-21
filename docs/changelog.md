# Changelog

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
