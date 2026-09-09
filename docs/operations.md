# 运维与排障

## 日常

```bash
lm status                    # 总览：权重/模型/磁盘
lm sync                      # 刷新 models-registry 中 Ollama 列表
ollama ps                    # 当前已加载模型
```

卸载 Ollama 模型（走统一入口，执行前确认提示）：

```bash
lm rm <name|tier>            # 例：lm rm fast  /  lm rm qwen3.5:9b
lm rm <name> --yes           # 跳过确认（脚本用）
```

删除后会自动 `lm sync` 回写 registry；若仍在 `models.manifest` 中，用 `lm deploy` 重装。

强制重拉已装模型：`lm deploy --force`（或 `lm deploy main --force`）。

`lm deploy` 开始前会对照 GitHub latest 检查 Ollama 版本：落后则提示是否先升级（`Y` 自动装官方 darwin 包到 `/opt/homebrew/opt/ollama-upstream`；`n` 跳过并继续 deploy）。

```bash
lm deploy --yes                  # 落后时不询问，直接升级 Ollama 再部署
lm deploy --skip-ollama-upgrade  # 跳过版本检查
lm upgrade-ollama                # 单独检查/安装/升级运行时（未装则提示安装）
lm upgrade-ollama --check-only   # 只报告（exit 2=落后，3=未安装）
```

## 新机初始化

```bash
lm init --dry-run            # 依赖报告 + 探测芯片/内存，打印 profile 或 fallback 方案
lm init                      # 先检查软件依赖（缺 ollama/mflux/mlx-* 时提示自动安装）→ 确认后写 config/*.manifest（默认不 deploy）
lm init --deploy             # 写完后 lm deploy 并 pull 图/语音权重
lm init --skip-deps          # 跳过依赖检查（CI / 只改清单）
```

依赖检查只覆盖引擎层（ollama / mflux / mlx-whisper / mlx-audio / espeak-ng），按 `--stack`
范围裁剪；模型权重仍由 manifest 驱动。Ollama 缺失时走 `lm upgrade-ollama` 的全新安装路径
（GitHub latest → `/opt/homebrew/opt/ollama-upstream` + LaunchAgent）。

精确表与 lineup 见 [hardware-profiles.md](./hardware-profiles.md)。已初始化的机器日常换代用下面的 `lm update`（只动 main/deep/fast）。

## 更新模型

### 推荐：硬件感知自动更新三档

```bash
lm update --dry-run          # 只看推荐，不改清单
lm update                    # 探测本机内存/芯片 → 远程评分 → 确认后写 manifest 并 deploy
lm update --ram 64           # 硬件覆盖（未提供则自动探测）
lm update --no-deploy        # 只改 manifest，稍后手动 lm deploy
```

策略在 `config/update-policy.conf`（家族优先级、量化偏好、内存预留、稳定性阈值）；**安装 SSOT 仍是** `config/models.manifest`。

### 指定/模糊搜索单个模型

```bash
lm get qwen3.8               # 多个家族/tag 时交互选择
lm get "35b-a3b-q4"          # 模糊
lm get ornith --tier main    # 下载并写入 main 档
lm get qwen3-embedding:8b --tier embed --yes
lm get gemma4:31b --tier chat --yes
lm get qwen3.8:27b-q4_K_M --tier main --yes
lm get qwen3.8:27b-q8_0 --tier deep --yes
lm get qwen3.5:9b --yes      # 非交互（多候选时取策略优先的第一项）
```

### 校验

```bash
lm check                     # manifest 对账
lm test all-llm              # 全角色冒烟（大模型串行）
lm test embed && lm test rerank
lm test reason && lm test asr && lm test tts
lm asr ~/path/audio.wav --lang zh
lm tts "Hello from local TTS" --voice af_heart
lm tts "你好，本地语音合成" --voice zf_xiaoxiao --lang z
```

### 语音 ASR

```bash
uv tool install mlx-whisper   # 若未装
lm pull-speech                # 权重 → ~/models/speech/
lm asr meeting.m4a --lang zh
```

### 语音 TTS

```bash
brew install espeak-ng        # 英语音素（Kokoro/misaki[en] 需要）
uv tool install mlx-audio --with 'misaki[en]' --with 'misaki[zh]'
# spaCy 英语小模型须装进 mlx-audio 的 tool 环境（misaki 会尝试 uv pip，易失败）：
uv pip install --python "$(dirname "$(command -v mlx_audio.tts.generate)")/python" \
  https://github.com/explosion/spacy-models/releases/download/en_core_web_sm-3.8.0/en_core_web_sm-3.8.0-py3-none-any.whl
lm pull-tts                   # 权重 → ~/models/tts/（Kokoro-82M-bf16，约 375MB）
lm tts "Hello" --play
lm tts "你好世界" --voice zf_xiaoxiao --lang z -o ~/Desktop/tts-out
# 本机最强质量档（~4GB）：
lm pull-tts mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-bf16
lm tts "你好，欢迎使用本地语音合成。" --model qwen3-tts-1.7b --voice Vivian \
  --instruct "平静清晰" --play
lm test tts
```

### LM Studio GGUF

```bash
lm pull-gguf main deep fast --link   # → ~/models/gguf/（symlink 到 LM Studio）
# 与 Ollama 权重分离；可并存，勿同时在两边加载同一个大模型吃满 48GB
```

### 手动

1. 改 `config/models.manifest` 或 `ollama pull <name>`
2. `lm deploy` / 更新 `docs/models-registry.md`
3. 若默认 Agent 模型变了：改 `docs/agent-integration.md`
4. 写 `docs/changelog.md`（`lm update` 会自动追加一条）

## 磁盘

- 权重统一在 `~/models/`（ollama/ gguf/ image-gen/），**不要**放进本仓库；`~/.ollama/models` 是 symlink
- 三档齐备约 80–100 GB；用 `du -sh ~/models` 检查

## 故障排查

| 现象 | 检查 |
|------|------|
| &lt;25 tok/s 或卡顿 | 是否加载了第二个大模型；上下文是否过大；Ollama 是否够新（MLX） |
| Agent 连不上 | `ollama serve` / `curl :11434/api/tags`；Base URL 是否带 `/v1` |
| OOM / 换页狂转 | 卸模型；降低上下文；A 档不要与 VL 同开 |
| VL 很慢 | 确认 LM Studio 使用 MLX；减少图分辨率与张数 |

## 内存纪律（48GB）

- 只常驻一个大模型
- A 档运行时减少其它重应用
- 超长文档优先 RAG，不要硬塞 128K+
