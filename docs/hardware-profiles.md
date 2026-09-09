# 硬件档案与 `lm init`

新机器用 **`lm init`** 按本机 Apple Silicon 配置初始化 `config/*.manifest`。
安装 SSOT 仍是清单文件本身；本页与 `config/hardware-profiles.tsv` / `config/lineups.tsv` 只是配方，**不是**部署来源。

`lm update` / `lm deploy` / `lm get` 语义不变：日常换代仍走 `lm update`（只给 main/deep/fast 打分，策略在 `config/update-policy.conf`）。

## 决策

0. **依赖检查**（[`scripts/lib/deps.sh`](../scripts/lib/deps.sh)）：按 `--stack` 范围检查
   ollama / mflux / mlx-whisper / mlx-audio / espeak-ng；缺失时提示自动安装，装完继续。
   `--yes` 免询问自动装；`--dry-run` 只报告；`--skip-deps` 跳过；非交互 stdin 仅告警。
1. 探测芯片、统一内存、可选 GPU 核数 / Model Identifier
2. **精确匹配** `(family, variant, mem_bucket)` 对照 [`config/hardware-profiles.tsv`](../config/hardware-profiles.tsv)
3. 命中 → 使用命名 lineup（[`config/lineups.tsv`](../config/lineups.tsv)），离线、确定
4. 未命中（M1/M2、非标准内存、Linux 等）→ `config/init-policy.conf` + 远程 Ollama 打分（main/deep/fast 复用现有 `recommend_tiers`，窗口按 RAM 缩放）
5. 默认只写清单，不拉权重；`--deploy` 才 `lm deploy` 并 pull image/asr/tts

不做「最接近 RAM」的模糊命中（避免 36GB 误用 48GB 方案）。

## 命令

```bash
lm init --dry-run                 # 只看依赖 + 硬件 + 方案（不安装、不写清单）
lm init                           # 依赖检查（缺则提示安装）→ 确认后写清单
lm init --yes                     # 跳过确认（缺失依赖也直接自动安装）
lm init --stack llm               # 只写 models.manifest
lm init --skip-deps               # 跳过依赖检查阶段
lm init --deploy                 # 写完后部署
lm init --ram 48 --chip "Apple M5 Max"   # 覆盖探测
```

探测来源（Darwin）：`sysctl hw.memsize`、`machdep.cpu.brand_string`，以及 `system_profiler` / `ioreg`（Model Identifier、GPU 核数）。

## 内存桶

探测到的 GB 会贴到常见苹果统一内存档：`8 / 16 / 18 / 24 / 32 / 36 / 48 / 64 / 96 / 128 / 192`（±2GB 内）。对不上的容量（例如 40GB）保持原值，精确表不命中，走 fallback。

芯片解析：`Apple M5 Max` → `family=m5` `variant=max`；无 Pro/Max/Ultra 后缀则为 `base`。

## Lineup（按统一内存，不按「是否 M5」）

| lineup | 典型 RAM | LLM | 图 / 语音 |
|--------|----------|-----|-----------|
| `lite-16` | 16–18GB | main≈9B；无独立 deep/chat/reason | Klein；ASR turbo；Kokoro |
| `std-24` | 24GB | main≈9B | 同上，无 Z-Image / TTS-alt |
| `std-32` | 32GB | main 27B Q4（紧）；无 Q8 deep、无 31B chat | Klein；Kokoro |
| `std-36` | 36GB | 27B Q4 main；Q8 deep 需独占 | Klein + Z-Image；TTS-alt |
| `full-48` | 48GB | 当前 v2.9 清单（本机金标准） | 双图模 + Kokoro + Qwen3-TTS |
| `plus-64` | 64GB | main 升 27B Q8；仍不默认 70B+ | 同 full-48 |
| `ultra-128` | 96GB+ | deep 允许 120B 级独占 | 同 full-48 |

一次只常驻一个大模型：≥18GB 的 main / deep / chat / 120B deep 互斥加载。

## 常见 Mac SKU → lineup

摘自 `hardware-profiles.tsv`（同一 lineup 可被多 SKU 复用）。M1/M2 不进表。

| 芯片 | 内存 | lineup |
|------|------|--------|
| M3 / M4 / M5 | 16GB | lite-16 |
| M3 / M4 / M5 | 24GB | std-24 |
| M3 Pro | 18GB | lite-16 |
| M4 | 32GB | std-32 |
| M3 Pro / M3 Max / M4 Max | 36GB | std-36 |
| M3–M5 Max/Pro 等 | 48GB | full-48 |
| Max / Ultra | 64GB | plus-64 |
| M3–M5 Max 128GB / Ultra 96–192GB | ultra-128 |

本机 **M5 Max / 48GB / Mac17,6** 对应 `m5-max-48` → `full-48`，与已提交的四份 manifest 逐字段一致（`lm init --dry-run` 应为 same）。

## 与 `lm update` 的分工

| | `lm init` | `lm update` |
|--|-----------|-------------|
| 用途 | 新机 / 换机初始化全角色清单 | 已有清单上刷新 **main/deep/fast** |
| 精确表 | 有 | 无 |
| 策略文件 | `init-policy.conf`（仅 fallback） | `update-policy.conf` |
| 默认是否 deploy | 否（`--deploy` 才拉） | 确认后会 deploy |
| 48GB 绝对上限 | fallback 按 usable RAM 缩放 | 保持原 `MAIN_ABS_MAX=28` 等，**不改** |

改 pin：编辑 `config/lineups.tsv` 或 `hardware-profiles.tsv`，不是改脚本。
